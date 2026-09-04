import 'dart:convert';

import 'api_http_client.dart';
import 'auth_api.dart';

class DeviceInfo {
  DeviceInfo({
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    required this.status,
    required this.registeredAt,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String platform;
  final String appVersion;
  final String status;
  final int registeredAt;
  final int lastSeenAt;

  factory DeviceInfo.fromJson(Map<String, dynamic> m) => DeviceInfo(
        deviceId: (m['device_id'] as String?) ?? '',
        platform: (m['platform'] as String?) ?? '',
        appVersion: (m['app_version'] as String?) ?? '',
        status: (m['status'] as String?) ?? 'ACTIVE',
        registeredAt: (m['registered_at'] as num?)?.toInt() ?? 0,
        lastSeenAt: (m['last_seen_at'] as num?)?.toInt() ?? 0,
      );
}

class DevicesApi {
  DevicesApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  String _url(String path) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$root$path';
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<List<DeviceInfo>> list() async {
    final res = await apiHttpClient
        .get(Uri.parse(_url('/api/devices')), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效', statusCode: 401);
    }
    if (res.statusCode != 200) {
      throw ApiException('获取设备失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['devices'] as List? ?? [])
        .whereType<Map>()
        .map((e) => DeviceInfo.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> revoke(String deviceId) async {
    final enc = Uri.encodeComponent(deviceId);
    final res = await apiHttpClient
        .delete(
          Uri.parse(_url('/api/devices/$enc')),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效', statusCode: 401);
    }
    if (res.statusCode != 200) {
      String msg = '吊销失败（${res.statusCode}）';
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['detail'] != null) msg = m['detail'].toString();
      } catch (_) {}
      throw ApiException(msg, statusCode: res.statusCode);
    }
  }
}
