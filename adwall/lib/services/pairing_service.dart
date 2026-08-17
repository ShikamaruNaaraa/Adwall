import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
/// Base URL of the AdWall pairing backend (the Next.js API routes in
/// /next/app/api), read from the API_BASE_URL key in .env (loaded once in
/// main_admin.dart / main_tv.dart before runApp()). Edit .env directly to
/// point at your machine's LAN IP when testing on a physical device or TV.
String get _apiBaseUrl =>
    dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';

class PairingException implements Exception {
  PairingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Connects the Admin app and the TV app through a short-lived 6-digit
/// pairing code, via the backend's REST + Server-Sent Events API:
///   POST /api/codes                - create a code for a nickname
///   POST /api/codes/{code}/claim   - TV claims a code
///   GET  /api/codes/{code}/events  - admin gets pushed status updates (SSE)
class PairingService {
  PairingService({String? baseUrl}) : _baseUrl = baseUrl ?? _apiBaseUrl;

  static const _deviceIdKey = 'tv_device_id';
  static const _pairedCodeKey = 'tv_paired_code';
  static const _pairedNicknameKey = 'tv_paired_nickname';

  final String _baseUrl;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_baseUrl.hashCode}';
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  Future<PairedTv?> getSavedPairing() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_pairedCodeKey);
    final nickname = prefs.getString(_pairedNicknameKey);
    if (code == null || nickname == null) return null;
    return PairedTv(code: code, nickname: nickname);
  }

  Future<void> savePairing({required String code, required String nickname}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairedCodeKey, code);
    await prefs.setString(_pairedNicknameKey, nickname);
  }

  Future<void> clearPairing() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairedCodeKey);
    await prefs.remove(_pairedNicknameKey);
  }


  /// Turns a relative path the backend hands back (e.g. '/media/abc.png')
  /// into a full URL the Flutter side can load images/video from.
  String resolveMediaUrl(String path) =>
      path.startsWith('http') ? path : '$_baseUrl$path';

  /// Admin side: create a new 6-digit code labelled with [nickname].
  Future<String> createPairingCode(String nickname) async {
    final res = await http.post(
      _uri('/api/codes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nickname': nickname}),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['code'] as String;
  }

  /// Admin side: live updates for a code, pushed over Server-Sent Events
  /// (GET /api/codes/{code}/events). Emits a map with 'status'
  /// ('pending'/'paired'), 'nickname', 'media_type', 'media_url' each time
  /// the server sends one - starting with the current state on connect.
  Stream<Map<String, dynamic>> watchPairing(String code) {
    final controller = StreamController<Map<String, dynamic>>();
    final client = http.Client();

    () async {
      try {
        final request = http.Request('GET', _uri('/api/codes/$code/events'));
        final response = await client.send(request);
        if (response.statusCode != 200) {
          controller.addError(
            PairingException(
              'Failed to open status stream (${response.statusCode})',
            ),
          );
          await controller.close();
          return;
        }

        var buffer = '';
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          buffer += chunk;
          // SSE frames are separated by a blank line; each frame may have
          // one or more "data: ..." lines.
          while (buffer.contains('\n\n')) {
            final frameEnd = buffer.indexOf('\n\n');
            final frame = buffer.substring(0, frameEnd);
            buffer = buffer.substring(frameEnd + 2);

            final dataLines = frame
                .split('\n')
                .where((l) => l.startsWith('data:'))
                .map((l) => l.substring(5).trim())
                .join();
            if (dataLines.isEmpty) continue;
            try {
              controller.add(jsonDecode(dataLines) as Map<String, dynamic>);
            } catch (_) {
              // Ignore malformed/partial frames.
            }
          }
        }
        await controller.close();
      } catch (e) {
        controller.addError(PairingException(e.toString()));
        await controller.close();
      } finally {
        client.close();
      }
    }();

    return controller.stream;
  }

  /// TV side: claim a code the user typed in. Returns the admin-chosen
  /// nickname on success.
  Future<String> claimCode(String code, {required String tvDeviceId}) async {
    final res = await http.post(
      _uri('/api/codes/$code/claim'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'tv_device_id': tvDeviceId}),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['nickname']
        as String;
  }

  /// Admin side: every TV currently paired, so the admin can pick one to
  /// send an image/video to.
  Future<List<TvSummary>> fetchTvs() async {
    final res = await http.get(_uri('/api/tvs'));
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => TvSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PlaylistItem>> uploadMedia(String code, {
    required String filePath,
    required String fileName,
    required int durationSeconds,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/api/codes/$code/media'));
    req.fields['duration_seconds'] = durationSeconds.toString();
    req.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      filename: fileName,
    ));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['playlist'] as List<dynamic>)
        .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }


  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['detail']?.toString() ??
          'Request failed (${res.statusCode})';
    } catch (_) {
      return 'Request failed (${res.statusCode})';
    }
  }
}

class PlaylistItem {
  const PlaylistItem({
    required this.mediaType,
    required this.mediaUrl,
    required this.durationSeconds,
  });

  factory PlaylistItem.fromJson(Map<String, dynamic> json) => PlaylistItem(
        mediaType: json['mediaType'] as String? ??
            json['media_type'] as String? ?? 'image',
        mediaUrl: json['mediaUrl'] as String? ?? json['media_url'] as String,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ??
            (json['duration_seconds'] as num?)?.toInt() ?? 10,
      );

  final String mediaType;
  final String mediaUrl;
  final int durationSeconds;
}

class TvSummary {
  const TvSummary({
    required this.code,
    required this.nickname,
    required this.playlist,
  });

  factory TvSummary.fromJson(Map<String, dynamic> json) => TvSummary(
        code: json['code'] as String,
        nickname: json['nickname'] as String,
        playlist: (json['playlist'] as List<dynamic>? ?? [])
            .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String code;
  final String nickname;
  final List<PlaylistItem> playlist;
}

class PairedTv {
  const PairedTv({required this.code, required this.nickname});

  final String code;
  final String nickname;
}
