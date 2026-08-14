import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

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

  final String _baseUrl;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

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

  /// Admin side: upload an image/video file and push it to the TV paired
  /// under [code]. Returns the resolved media URL the TV will load.
  Future<String> uploadMedia(String code, {
    required String filePath,
    required String fileName,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/api/codes/$code/media'));
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
    return resolveMediaUrl(body['media_url'] as String);
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

/// A TV the admin has paired with, as returned by GET /tvs.
class TvSummary {
  const TvSummary({
    required this.code,
    required this.nickname,
    required this.mediaType,
    required this.mediaUrl,
  });

  factory TvSummary.fromJson(Map<String, dynamic> json) => TvSummary(
        code: json['code'] as String,
        nickname: json['nickname'] as String,
        mediaType: json['media_type'] as String?,
        mediaUrl: json['media_url'] as String?,
      );

  final String code;
  final String nickname;
  final String? mediaType; // "image" | "video" | null
  final String? mediaUrl;
}
