import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
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

  static const _loggedInAdminKey = 'logged_in_admin_username';
  static const _adminTokenKey = 'logged_in_admin_token';

  Future<void> saveLoggedInAdmin(String username, {String? token}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loggedInAdminKey, username);
    if (token != null) {
      await prefs.setString(_adminTokenKey, token);
    }
  }

  Future<String?> getLoggedInAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_loggedInAdminKey);
  }

  Future<String?> _getAdminToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_adminTokenKey);
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _getAdminToken();
    return token != null ? {'Authorization': 'Bearer $token'} : {};
  }

  Future<void> clearLoggedInAdmin() async {
    final token = await _getAdminToken();
    if (token != null) {
      try {
        await http.post(
          _uri('/api/admins/logout'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } catch (_) {
        // Best-effort server-side revoke; still clear local state below.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loggedInAdminKey);
    await prefs.remove(_adminTokenKey);
  }

  /// Turns a relative path the backend hands back (e.g. '/media/abc.png')
  /// into a full URL the Flutter side can load images/video from.
  String resolveMediaUrl(String path) =>
      path.startsWith('http') ? path : '$_baseUrl$path';

  /// Admin side: create a new 6-digit code labelled with [nickname],
  /// attributed to the currently logged-in admin via their session token.
  Future<String> createPairingCode(String nickname) async {
    final res = await http.post(
      _uri('/api/codes'),
      headers: {'Content-Type': 'application/json', ...await _authHeaders()},
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
  /// Reconnects automatically (with a short delay) if the underlying HTTP
  /// stream ends or errors for any reason other than the caller cancelling
  /// the subscription, so a dropped connection doesn't silently stop
  /// delivering updates (e.g. playlist/ad removals) until the app restarts.
  Stream<Map<String, dynamic>> watchPairing(String code) {
    final controller = StreamController<Map<String, dynamic>>();
    http.Client? activeClient;
    var cancelled = false;
    controller.onCancel = () {
      cancelled = true;
      activeClient?.close();
    };

    Future<void> connectOnce() async {
      final client = http.Client();
      activeClient = client;
      // The server sends a ": ping" heartbeat frame every 15s (see
      // events/route.js) even when nothing has changed, specifically so a
      // silently-dead connection (e.g. the server process was killed
      // without a clean TCP close ever reaching this client) doesn't leave
      // the read loop below waiting forever for bytes that will never
      // arrive. If we go this long without receiving anything, force the
      // connection closed so the outer retry loop reconnects.
      const staleTimeout = Duration(seconds: 35);
      Timer? staleTimer;
      void resetStaleTimer() {
        staleTimer?.cancel();
        staleTimer = Timer(staleTimeout, () => client.close());
      }

      try {
        final request = http.Request('GET', _uri('/api/codes/$code/events'));
        // A server restart can leave a new TCP/HTTP connection attempt
        // pending without ever returning headers. Time it out so it falls
        // through to the retry loop instead of requiring an app restart.
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          controller.addError(
            PairingException(
              'Failed to open status stream (${response.statusCode})',
            ),
          );
          return;
        }

        resetStaleTimer();
        var buffer = '';
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          if (cancelled) return;
          resetStaleTimer();
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
      } catch (e) {
        if (!cancelled) controller.addError(PairingException(e.toString()));
      } finally {
        staleTimer?.cancel();
        client.close();
      }
    }


    () async {
      while (!cancelled) {
        await connectOnce();
        if (cancelled) break;
        // The stream ended (server restart, network hiccup, proxy timeout,
        // etc.) without the caller cancelling - reconnect after a short
        // delay instead of leaving this subscription dead.
        await Future.delayed(const Duration(seconds: 3));
      }
      if (!controller.isClosed) await controller.close();
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

  /// Admin side: every TV currently paired that this admin registered - the
  /// backend scopes the result to admin_username so admins never see each
  /// other's TVs.
  Future<List<TvSummary>> fetchTvs() async {
    final res = await http.get(_uri('/api/tvs'), headers: await _authHeaders());
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => TvSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin side: permanently remove a TV. Closes its live connection (if
  /// any) and frees the pairing code for reuse. If this was the TV's own
  /// saved pairing, callers should also call [clearPairing]. Only succeeds
  /// for a TV registered by the currently logged-in admin.
  Future<void> deleteTv(String code) async {
    final res = await http.delete(_uri('/api/codes/$code'), headers: await _authHeaders());
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
  }

  Future<List<PlaylistItem>> uploadMedia(String code, {
    required String filePath,
    required String fileName,
    required int durationSeconds,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/api/codes/$code/media'));
    req.headers.addAll(await _authHeaders());
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

  /// Admin side: upload one ad and attach it to every TV in [codes], so the
  /// same file can be shown on multiple TVs without re-uploading it.
  /// Returns the code the ad was uploaded for -> that TV's updated playlist.
  /// All codes must belong to the currently logged-in admin.
  Future<Map<String, List<PlaylistItem>>> uploadMediaToTvs({
    required List<String> codes,
    required String filePath,
    required String fileName,
    required int durationSeconds,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/api/media'));
    req.headers.addAll(await _authHeaders());
    req.fields['duration_seconds'] = durationSeconds.toString();
    req.fields['codes'] = jsonEncode(codes);
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
    final results = body['results'] as Map<String, dynamic>;
    return results.map((code, playlist) => MapEntry(
          code,
          (playlist as List<dynamic>)
              .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
              .toList(),
        ));
  }


  /// Admin side: every service ad (admin-wide ad + duration + play
  /// interval), inserted automatically into every TV's ad sequence.
  Future<List<ServiceAd>> fetchServiceAds() async {
    final res = await http.get(_uri('/api/service-ads'));
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => ServiceAd.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceAd> createServiceAd({
    required String filePath,
    required String fileName,
    required int durationSeconds,
    required int interval,
    List<String>? targetTvCodes,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/api/service-ads'));
    req.fields['duration_seconds'] = durationSeconds.toString();
    req.fields['interval'] = interval.toString();
    if (targetTvCodes != null && targetTvCodes.isNotEmpty) {
      req.fields['target_tv_codes'] = jsonEncode(targetTvCodes);
    }
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
    return ServiceAd.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> deleteServiceAd(String id) async {
    final res = await http.delete(_uri('/api/service-ads/$id'));
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
  }

  /// Admin side: edit an existing service ad's duration and/or play
  /// interval (occurrence count) without re-uploading the image.
  Future<ServiceAd> updateServiceAd(
    String id, {
    int? durationSeconds,
    int? interval,
    bool updateTargetTvCodes = false,
    List<String>? targetTvCodes,
  }) async {
    final body = <String, dynamic>{};
    if (durationSeconds != null) body['duration_seconds'] = durationSeconds;
    if (interval != null) body['interval'] = interval;
    if (updateTargetTvCodes) {
      body['target_tv_codes'] =
          (targetTvCodes == null || targetTvCodes.isEmpty)
              ? null
              : targetTvCodes;
    }
    final res = await http.patch(
      _uri('/api/service-ads/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    return ServiceAd.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Admin side: edit the duration of one ad already on a TV's playlist
  /// (identified by its position) without re-uploading it.
  Future<List<PlaylistItem>> updatePlaylistItemDuration(
    String code, {
    required int index,
    required int durationSeconds,
  }) async {
    final res = await http.patch(
      _uri('/api/codes/$code/playlist'),
      headers: {'Content-Type': 'application/json', ...await _authHeaders()},
      body: jsonEncode({
        'index': index,
        'duration_seconds': durationSeconds,
      }),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['playlist'] as List<dynamic>)
        .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Admin side: rename one ad already on a TV's playlist (identified by
  /// its position) without re-uploading it.
  Future<List<PlaylistItem>> updatePlaylistItemName(
    String code, {
    required int index,
    required String name,
  }) async {
    final res = await http.patch(
      _uri('/api/codes/$code/playlist'),
      headers: {'Content-Type': 'application/json', ...await _authHeaders()},
      body: jsonEncode({
        'index': index,
        'name': name,
      }),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['playlist'] as List<dynamic>)
        .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Admin side: move one ad already on a TV's playlist from one position
  /// to another (drag-to-reorder), without touching any other item's data.
  Future<List<PlaylistItem>> reorderPlaylistItem(
    String code, {
    required int fromIndex,
    required int toIndex,
  }) async {
    final res = await http.patch(
      _uri('/api/codes/$code/playlist'),
      headers: {'Content-Type': 'application/json', ...await _authHeaders()},
      body: jsonEncode({
        'index': fromIndex,
        'to_index': toIndex,
      }),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['playlist'] as List<dynamic>)
        .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Admin side: remove one ad already on a TV's playlist (identified by
  /// its position).
  Future<List<PlaylistItem>> removePlaylistItem(String code, {required int index}) async {
    final uri = _uri('/api/codes/$code/playlist').replace(queryParameters: {
      'index': index.toString(),
    });
    final res = await http.delete(uri, headers: await _authHeaders());
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['playlist'] as List<dynamic>)
        .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Admin side: set a TV's display orientation ('landscape' or 'portrait').
  /// The TV app receives this over its live SSE stream and rotates its
  /// playback layout to match.
  Future<String> updateTvOrientation(String code, String orientation) async {
    final res = await http.patch(
      _uri('/api/codes/$code/orientation'),
      headers: {'Content-Type': 'application/json', ...await _authHeaders()},
      body: jsonEncode({'orientation': orientation}),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['orientation'] as String;
  }

  /// Admin side: set the slide transition a TV uses when its currently
  /// shown image changes to the next one ('none' or 'slide_left_to_right').
  /// The TV app receives this over its live SSE stream and animates
  /// accordingly.
  Future<String> updateTvTransition(String code, String transition) async {
    final res = await http.patch(
      _uri('/api/codes/$code/transition'),
      headers: {'Content-Type': 'application/json', ...await _authHeaders()},
      body: jsonEncode({'transition': transition}),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['transition'] as String;
  }



  static const _settingsChannel = MethodChannel('adwall/settings');

  /// TV side: whether the TV app should launch automatically when the TV
  /// turns on (Android "start on boot"). Backed by native SharedPreferences
  /// so a BroadcastReceiver can read it before any Dart code runs.
  Future<bool> getLaunchOnBoot() async {
    try {
      final result = await _settingsChannel.invokeMethod<bool>('getLaunchOnBoot');
      return result ?? false;
    } on MissingPluginException {
      // Not running on the tv flavor/Android build - treat as unsupported.
      return false;
    }
  }

  Future<void> setLaunchOnBoot(bool enabled) async {
    try {
      await _settingsChannel.invokeMethod('setLaunchOnBoot', {'enabled': enabled});
    } on MissingPluginException {
      // Not supported on this build - silently ignore.
    }
  }

  /// TV side: tell the backend this TV was manually disconnected (via the
  /// TV app's own "Disconnect" button), so the admin app shows it as
  /// disconnected rather than connected. The pairing/code itself stays
  /// valid.
  Future<void> disconnectTv(String code) async {
    final res = await http.post(_uri('/api/codes/$code/disconnect'));
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
  }

  Future<AdminLoginResult> adminLogin({
    required String username,
    required String password,
  }) async {
    final res = await http.post(
      _uri('/api/admins/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return AdminLoginResult(
      username: body['username'] as String,
      mustChangePassword: body['mustChangePassword'] as bool? ?? false,
      token: body['token'] as String,
    );
  }

  Future<void> changeAdminPassword({
    required String username,
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await http.post(
      _uri('/api/admins/$username/password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
  }

  /// Admin side: every saved TV group, used by the Group Animation section.
  Future<List<TvGroup>> fetchGroups() async {
    final res = await http.get(_uri('/api/groups'));
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => TvGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin side: create a group from an ordered list of TV codes (index 0
  /// is where the snake animation starts).
  Future<TvGroup> createGroup(String name, List<String> tvCodes) async {
    final res = await http.post(
      _uri('/api/groups'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'tv_codes': tvCodes}),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    return TvGroup.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Admin side: rename a group and/or replace its ordered TV list.
  Future<TvGroup> updateGroup(
    String id, {
    String? name,
    List<String>? tvCodes,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (tvCodes != null) body['tv_codes'] = tvCodes;
    final res = await http.patch(
      _uri('/api/groups/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
    return TvGroup.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> deleteGroup(String id) async {
    final res = await http.delete(_uri('/api/groups/$id'));
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
  }

  /// Admin side: starts the group animation - broadcasts the group's video
  /// to every connected TV in the group at once (see PlayGroupAnimation in
  /// lib/store.js on the backend), each rendering its own slice.
  Future<void> playGroupAnimation(String id) async {
    final res = await http.post(_uri('/api/groups/$id/play'));
    if (res.statusCode != 200) {
      throw PairingException(_errorMessage(res));
    }
  }

  /// Admin side: upload (or replace) the one video that plays stretched
  /// across this group's TVs, split into equal vertical slices.
  Future<TvGroup> uploadGroupAnimation(
    String id, {
    required String filePath,
    required String fileName,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/api/groups/$id/animation'));
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
    return TvGroup.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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
    this.name,
  });

  factory PlaylistItem.fromJson(Map<String, dynamic> json) => PlaylistItem(
        mediaType: json['mediaType'] as String? ?? 'image',
        mediaUrl: json['mediaUrl'] as String,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 10,
        name: json['name'] as String?,
      );

  final String mediaType;
  final String mediaUrl;
  final int durationSeconds;

  /// Display name of this ad. Falls back to the file name in [mediaUrl]
  /// when the backend hasn't sent one (older items).
  final String? name;

  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name! : mediaUrl.split('/').last;
}

class TvSummary {
  const TvSummary({
    required this.code,
    required this.nickname,
    required this.playlist,
    required this.connected,
    this.orientation = 'landscape',
    this.transition = 'none',
  });

  factory TvSummary.fromJson(Map<String, dynamic> json) => TvSummary(
        code: json['code'] as String,
        nickname: json['nickname'] as String,
        playlist: (json['playlist'] as List<dynamic>? ?? [])
            .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        // Whether the TV currently has a live connection to the backend.
        // Defaults to true for older backends that don't send this field.
        connected: json['connected'] as bool? ?? true,
        orientation: json['orientation'] as String? ?? 'landscape',
        transition: json['transition'] as String? ?? 'none',
      );

  final String code;
  final String nickname;
  final List<PlaylistItem> playlist;
  final bool connected;
  final String orientation;
  final String transition;
}


class PairedTv {
  const PairedTv({required this.code, required this.nickname});

  final String code;
  final String nickname;
}

class AdminLoginResult {
  const AdminLoginResult({
    required this.username,
    required this.mustChangePassword,
    required this.token,
  });

  final String username;
  final bool mustChangePassword;
  final String token;
}

/// An admin-wide ad that automatically plays on every registered TV, after
/// every [interval] regular ads that TV shows (clamped down to that TV's
/// own ad count, so a TV with only 1 ad still gets it after that 1 ad).
class ServiceAd {
  const ServiceAd({
    required this.id,
    required this.mediaType,
    required this.mediaUrl,
    required this.durationSeconds,
    required this.interval,
    this.targetTvCodes,
  });

  factory ServiceAd.fromJson(Map<String, dynamic> json) => ServiceAd(
        id: json['id'] as String,
        mediaType: json['mediaType'] as String? ?? 'image',
        mediaUrl: json['mediaUrl'] as String,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 10,
        interval: (json['interval'] as num?)?.toInt() ?? 1,
        targetTvCodes: (json['targetTvCodes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(),
      );

  final String id;
  final String mediaType;
  final String mediaUrl;
  final int durationSeconds;
  final int interval;

  /// TV codes this ad is restricted to. `null` means it plays on every TV.
  final List<String>? targetTvCodes;

  bool get appliesToAllTvs => targetTvCodes == null || targetTvCodes!.isEmpty;
}

/// An ordered set of TVs used for the Group Animation feature: the admin
/// attaches one video to the group, and playing it broadcasts that video
/// to every connected TV in `tvCodes` at once, each rendering only its own
/// equal vertical slice (stretched to fill its screen) so the TVs together
/// form one continuous wide video.
class TvGroup {
  const TvGroup({
    required this.id,
    required this.name,
    required this.tvCodes,
    this.animationMediaUrl,
    this.animationMediaType,
  });

  factory TvGroup.fromJson(Map<String, dynamic> json) => TvGroup(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        tvCodes: (json['tvCodes'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        animationMediaUrl: json['animationMediaUrl'] as String?,
        animationMediaType: json['animationMediaType'] as String?,
      );

  final String id;
  final String name;
  final List<String> tvCodes;

  /// Relative media path (e.g. '/media/abc.mp4') for the group's video,
  /// or null if none has been added yet.
  final String? animationMediaUrl;

  /// Always 'video'.
  final String? animationMediaType;

  bool get hasMedia => animationMediaUrl != null && animationMediaUrl!.isNotEmpty;
  bool get hasAnimation => hasMedia;
}
