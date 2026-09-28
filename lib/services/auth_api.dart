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

class UserProfile {
  UserProfile({
    required this.userId,
    required this.username,
    this.licensePlate,
    this.status = 'ACTIVE',
    this.plan = 'trial',
    this.expiresAt,
    this.daysLeft,
    this.writeAllowed = true,
    this.announcement = '',
    this.maxRounds = 0,
    this.maxAttachments = 0,
  });

  final int userId;
  final String username;
  final String? licensePlate;
  final String status;
  final String plan;
  final int? expiresAt;
  final int? daysLeft;
  final bool writeAllowed;
  final String announcement;
  final int maxRounds;
  final int maxAttachments;

  bool get isExpired => status == 'EXPIRED';
  bool get isTrial => plan == 'trial';

  factory UserProfile.fromJson(Map<String, dynamic> m) {
    final limits = (m['limits'] as Map?)?.cast<String, dynamic>() ?? {};
    return UserProfile(
      userId: (m['user_id'] as num?)?.toInt() ?? 0,
      username: (m['username'] as String?) ?? '',
      licensePlate: m['license_plate'] as String?,
      status: (m['status'] as String?) ?? 'ACTIVE',
      plan: (m['plan'] as String?) ?? 'trial',
      expiresAt: (m['expires_at'] as num?)?.toInt(),
      daysLeft: (m['days_left'] as num?)?.toInt(),
      writeAllowed: m['write_allowed'] != false,
      announcement: (m['announcement'] as String?) ?? '',
      maxRounds: (limits['max_rounds'] as num?)?.toInt() ?? 0,
      maxAttachments: (limits['max_attachments'] as num?)?.toInt() ?? 0,
    );
  }
}

class AuthResult {
  AuthResult({
    required this.token,
    required this.username,
    required this.userId,
    this.licensePlate,
    this.profile,
  });

  final String token;
  final String username;
  final int userId;
  final String? licensePlate;
  final UserProfile? profile;
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

  AuthResult _parseAuth(http.Response res) {
    _throwIfAuthError(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final profile = UserProfile.fromJson(m);
    return AuthResult(
      token: m['token'] as String,
      username: (m['username'] as String?) ?? profile.username,
      userId: (m['user_id'] as num?)?.toInt() ?? profile.userId,
      licensePlate: m['license_plate'] as String? ?? profile.licensePlate,
      profile: profile,
    );
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
    return _parseAuth(res);
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
    return _parseAuth(res);
  }

  Future<UserProfile> me(String token) async {
    final res = await apiHttpClient
        .get(Uri.parse(_url('/api/auth/me')), headers: _jsonHeaders(token))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录', statusCode: 401);
    }
    _throwIfAuthError(res);
    return UserProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<UserProfile> updateProfile({
    required String token,
    required String licensePlate,
  }) async {
    final res = await apiHttpClient
        .put(
          Uri.parse(_url('/api/auth/profile')),
          headers: _jsonHeaders(token),
          body: jsonEncode({'license_plate': licensePlate}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录', statusCode: 401);
    }
    _throwIfAuthError(res);
    return UserProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> changePassword({
    required String token,
    required String oldPassword,
    required String newPassword,
  }) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/auth/change-password')),
          headers: _jsonHeaders(token),
          body: jsonEncode({
            'old_password': oldPassword,
            'new_password': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录', statusCode: 401);
    }
    _throwIfAuthError(res);
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
