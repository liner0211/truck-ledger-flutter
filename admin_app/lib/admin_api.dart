import 'dart:convert';

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

  Future<List<Map<String, dynamic>>> users() async {
    final m = await _json('GET', '/api/admin/users');
    final list = m['users'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> setSetting(String key, String value) async {
    await _json('POST', '/api/admin/settings', body: {'key': key, 'value': value});
  }

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

  /// 用当前 JWT 换一次性网页登录票据，返回站内 path（如 /admin/sso?ticket=…）
  Future<String> createWebTicketPath(String redirect) async {
    final m = await _json('POST', '/api/admin/web-ticket', body: {
      'redirect': redirect,
    });
    final path = m['path']?.toString() ?? '';
    if (path.isEmpty) throw AdminApiException('未返回网页登录地址');
    return path;
  }

  /// 完整 URL，供系统浏览器打开与网页后台相同的页面
  Future<Uri> createWebTicketUri(String redirect) async {
    final path = await createWebTicketPath(redirect);
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root$path');
  }

  static String defaultBaseUrl() {
    if (kReleaseMode) return 'https://truck.liner0211.online';
    return 'https://truck.liner0211.online';
  }
}
