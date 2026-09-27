import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AdminApiException implements Exception {
  AdminApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class AdminProfile {
  AdminProfile({
    required this.id,
    required this.username,
    required this.role,
    required this.permissions,
  });

  final int id;
  final String username;
  final String role;
  final List<String> permissions;

  bool get isSuper => role == 'super';
  bool can(String p) => permissions.contains(p);
  String get roleLabel =>
      role == 'super' ? '开发者' : '会计管理员';

  factory AdminProfile.fromJson(Map<String, dynamic> m) => AdminProfile(
        id: (m['id'] as num).toInt(),
        username: m['username'] as String? ?? '',
        role: m['role'] as String? ?? 'operator',
        permissions: (m['permissions'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

class AdminApi {
  AdminApi({required this.baseUrl, this.token});

  String baseUrl;
  String? token;

  Uri _u(String path) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root$path');
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Map<String, String> _headersWithPlatform() {
    final h = Map<String, String>.from(_headers);
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        h['X-App-Platform'] = 'android';
      } else if (Platform.isIOS) {
        h['X-App-Platform'] = 'ios';
      } else if (Platform.isLinux) {
        h['X-App-Platform'] = 'linux';
      } else if (Platform.isWindows) {
        h['X-App-Platform'] = 'windows';
      }
    }
    return h;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _u(path);
    late http.Response res;
    if (method == 'GET') {
      res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
    } else if (method == 'DELETE') {
      res = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 30));
    } else if (method == 'PUT') {
      res = await http
          .put(uri, headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 60));
    } else {
      res = await http
          .post(uri, headers: _headers, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 30));
    }
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) data = decoded;
      if (decoded is Map) data = decoded.cast<String, dynamic>();
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = data?['detail']?.toString() ?? '请求失败（${res.statusCode}）';
      throw AdminApiException(detail, statusCode: res.statusCode);
    }
    return data ?? {};
  }

  Future<({String token, AdminProfile admin})> login(String username, String password) async {
    final m = await _json('POST', '/api/admin/login', body: {
      'username': username,
      'password': password,
    });
    final t = m['access_token'] as String? ?? '';
    final admin = AdminProfile.fromJson((m['admin'] as Map).cast<String, dynamic>());
    token = t;
    return (token: t, admin: admin);
  }

  Future<AdminProfile> me() async {
    final m = await _json('GET', '/api/admin/me');
    return AdminProfile.fromJson(m);
  }

  Future<Map<String, dynamic>> dashboard() => _json('GET', '/api/admin/dashboard');

  Future<Map<String, dynamic>> allSettings() async {
    final m = await _json('GET', '/api/admin/settings');
    return (m['settings'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<List<Map<String, dynamic>>> audits({int limit = 30}) async {
    final m = await _json('GET', '/api/admin/audits?limit=$limit');
    final list = m['audits'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<List<Map<String, dynamic>>> users() async {
    final m = await _json('GET', '/api/admin/users');
    final list = m['users'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> setSetting(String key, String value) async {
    await _json('POST', '/api/admin/settings', body: {'key': key, 'value': value});
  }

  Future<List<Map<String, dynamic>>> userDevices(int userId) async {
    final m = await _json('GET', '/api/admin/users/$userId/devices');
    final list = m['devices'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<String> revokeUserDevice(int userId, String deviceId) async {
    final enc = Uri.encodeComponent(deviceId);
    final m = await _json('POST', '/api/admin/users/$userId/devices/$enc/revoke');
    return m['detail']?.toString() ?? '已吊销';
  }

  Future<List<Map<String, dynamic>>> userSnapshots(int userId) async {
    final m = await _json('GET', '/api/admin/users/$userId/snapshots');
    final list = m['snapshots'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> restoreUserSnapshot(int userId, int snapshotId) =>
      _json('POST', '/api/admin/users/$userId/snapshots/$snapshotId/restore');

  Future<String> userAction(int id, String action, {Map<String, dynamic>? body}) async {
    final m = await _json('POST', '/api/admin/users/$id/$action', body: body);
    return m['detail']?.toString() ?? '完成';
  }

  Future<String> deleteUser(int id) async {
    final m = await _json('DELETE', '/api/admin/users/$id');
    return m['detail']?.toString() ?? '已删除';
  }

  Future<void> push({required String title, required String body, int userId = 0}) async {
    await _json('POST', '/api/admin/push', body: {
      'title': title,
      'body': body,
      'user_id': userId,
    });
  }

  Future<List<Map<String, dynamic>>> operators() async {
    final m = await _json('GET', '/api/admin/operators');
    final list = m['admins'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> createOperator(String username, String password) async {
    await _json('POST', '/api/admin/operators', body: {
      'username': username,
      'password': password,
    });
  }

  Future<void> setOperatorEnabled(int id, bool enabled) async {
    await _json('POST', '/api/admin/operators/$id/${enabled ? 'enable' : 'disable'}');
  }

  Future<void> resetOperatorPassword(int id, String password) async {
    await _json('POST', '/api/admin/operators/$id/reset-password', body: {
      'password': password,
    });
  }

  Future<String> deleteOperator(int id) async {
    final m = await _json('DELETE', '/api/admin/operators/$id');
    return m['detail']?.toString() ?? '已删除';
  }

  Future<Map<String, dynamic>> userLedger(int userId) =>
      _json('GET', '/api/admin/users/$userId/ledger');

  Future<Map<String, dynamic>> putUserLedger(int userId, Map<String, dynamic> body) {
    final payload = Map<String, dynamic>.from(body);
    payload['force'] = true;
    return _json('PUT', '/api/admin/users/$userId/ledger', body: payload);
  }

  Map<String, String> get _authOnlyHeaders => {
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<List<int>> downloadAttachment(int userId, String filename) async {
    final enc = Uri.encodeComponent(filename);
    final res = await http
        .get(_u('/api/admin/users/$userId/attachments/$enc'), headers: _authOnlyHeaders)
        .timeout(const Duration(seconds: 60));
    if (res.statusCode == 404) {
      throw AdminApiException('附件不存在：$filename', statusCode: 404);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AdminApiException('下载附件失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  Future<void> uploadAttachment(int userId, String filename, List<int> bytes) async {
    final enc = Uri.encodeComponent(filename);
    final req = http.MultipartRequest(
      'POST',
      _u('/api/admin/users/$userId/attachments/$enc'),
    );
    req.headers.addAll(_authOnlyHeaders);
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AdminApiException('上传附件失败（${res.statusCode}）', statusCode: res.statusCode);
    }
  }

  Future<void> sendReconcileMessage(
    int userId, {
    required String title,
    required String body,
    String tripId = '',
    String tripTitle = '',
    List<({String filename, List<int> bytes})> images = const [],
  }) async {
    final req = http.MultipartRequest('POST', _u('/api/admin/users/$userId/messages'));
    req.headers.addAll(_authOnlyHeaders);
    req.fields['title'] = title;
    req.fields['body'] = body;
    req.fields['trip_id'] = tripId;
    req.fields['trip_title'] = tripTitle;
    for (final img in images) {
      req.files.add(http.MultipartFile.fromBytes('images', img.bytes, filename: img.filename));
    }
    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) data = decoded.cast<String, dynamic>();
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AdminApiException(
        data?['detail']?.toString() ?? '发送失败（${res.statusCode}）',
        statusCode: res.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> checkAdminAppUpdate(String appVersion) async {
    final uri = _u('/api/admin/app/check');
    final res = await http
        .post(
          uri,
          headers: _headersWithPlatform(),
          body: jsonEncode({'app_version': appVersion}),
        )
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) data = decoded.cast<String, dynamic>();
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AdminApiException(
        data?['detail']?.toString() ?? '检查更新失败（${res.statusCode}）',
        statusCode: res.statusCode,
      );
    }
    return data ?? {};
  }

  static String defaultBaseUrl() {
    if (kReleaseMode) return 'https://truck.liner0211.online';
    return 'https://truck.liner0211.online';
  }
}
