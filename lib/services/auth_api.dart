import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_http_client.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthResult {
  AuthResult({
    required this.token,
    required this.username,
    required this.userId,
    this.licensePlate,
  });

  final String token;
  final String username;
  final int userId;
  final String? licensePlate;
}

class AuthApi {
  AuthApi({required this.baseUrl});

  final String baseUrl;

  String _url(String path) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$root$path';
  }

  Map<String, String> _jsonHeaders([String? token]) => {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<void> checkHealth() async {
    final res = await apiHttpClient
        .get(Uri.parse(_url('/api/health')))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw ApiException('服务器不可用（${res.statusCode}）', statusCode: res.statusCode);
    }
  }

  Future<AuthResult> register({
    required String username,
    required String password,
    required String licensePlate,
  }) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/auth/register')),
          headers: _jsonHeaders(),
          body: jsonEncode({
            'username': username,
            'password': password,
            'license_plate': licensePlate,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _throwIfAuthError(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return AuthResult(
      token: m['token'] as String,
      username: m['username'] as String,
      userId: m['user_id'] as int,
      licensePlate: m['license_plate'] as String?,
    );
  }

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/auth/login')),
          headers: _jsonHeaders(),
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    _throwIfAuthError(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return AuthResult(
      token: m['token'] as String,
      username: m['username'] as String,
      userId: m['user_id'] as int,
      licensePlate: m['license_plate'] as String?,
    );
  }

  void _throwIfAuthError(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String msg = '请求失败（${res.statusCode}）';
    try {
      final m = jsonDecode(res.body);
      if (m is Map && m['detail'] != null) {
        final d = m['detail'];
        msg = d is String ? d : d.toString();
      }
    } catch (_) {}
    throw ApiException(msg, statusCode: res.statusCode);
  }
}
