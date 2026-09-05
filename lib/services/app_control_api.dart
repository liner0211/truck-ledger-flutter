import 'dart:convert';

import 'api_http_client.dart';
import 'auth_api.dart';
import 'feature_flags.dart';

class AppUpdateInfo {
  AppUpdateInfo({
    required this.available,
    required this.force,
    this.reason,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.latestVersion,
    required this.minVersion,
  });

  final bool available;
  final bool force;
  final String? reason;
  final String downloadUrl;
  final String releaseNotes;
  final String latestVersion;
  final String minVersion;

  factory AppUpdateInfo.fromJson(Map<String, dynamic>? m) {
    m ??= const {};
    return AppUpdateInfo(
      available: m['available'] == true,
      force: m['force'] == true,
      reason: m['reason'] as String?,
      downloadUrl: (m['download_url'] as String?) ?? '',
      releaseNotes: (m['release_notes'] as String?) ?? '',
      latestVersion: (m['latest_version'] as String?) ?? '',
      minVersion: (m['min_version'] as String?) ?? '',
    );
  }
}

class AppControlResult {
  AppControlResult({
    required this.allowed,
    this.reason,
    required this.appStatus,
    required this.minVersion,
    required this.latestVersion,
    required this.forceUpdate,
    required this.maintenanceMessage,
    required this.announcement,
    required this.controlVersion,
    required this.offlineGraceSec,
    this.account,
    FeatureFlags? featureFlags,
    AppUpdateInfo? update,
  })  : featureFlags = featureFlags ?? FeatureFlags(),
        update = update ??
            AppUpdateInfo(
              available: false,
              force: false,
              downloadUrl: '',
              releaseNotes: '',
              latestVersion: '',
              minVersion: '',
            );

  final bool allowed;
  final String? reason;
  final String appStatus;
  final String minVersion;
  final String latestVersion;
  final bool forceUpdate;
  final String maintenanceMessage;
  final String announcement;
  final int controlVersion;
  final int offlineGraceSec;
  final UserProfile? account;
  final FeatureFlags featureFlags;
  final AppUpdateInfo update;

  factory AppControlResult.fromJson(Map<String, dynamic> m) {
    final app = (m['app'] as Map?)?.cast<String, dynamic>() ?? {};
    final policy = (m['policy'] as Map?)?.cast<String, dynamic>() ?? {};
    final updateMap = (m['update'] as Map?)?.cast<String, dynamic>();
    UserProfile? account;
    final acc = m['account'];
    if (acc is Map<String, dynamic>) {
      account = UserProfile.fromJson(acc);
    } else if (acc is Map) {
      account = UserProfile.fromJson(acc.cast<String, dynamic>());
    }
    return AppControlResult(
      allowed: m['allowed'] == true,
      reason: m['reason'] as String?,
      appStatus: (app['status'] as String?) ?? 'ACTIVE',
      minVersion: (app['min_version'] as String?) ?? '1.0.0',
      latestVersion: (app['latest_version'] as String?) ?? '1.0.0',
      forceUpdate: app['force_update'] == true,
      maintenanceMessage: (app['maintenance_message'] as String?) ?? '',
      announcement: (app['announcement'] as String?) ?? '',
      controlVersion: (app['control_version'] as num?)?.toInt() ?? 1,
      offlineGraceSec: (policy['offline_grace_sec'] as num?)?.toInt() ?? 259200,
      account: account,
      featureFlags: FeatureFlags.tryParse(m['feature_flags']),
      update: AppUpdateInfo.fromJson(updateMap),
    );
  }
}

class AppControlApi {
  AppControlApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  String _url(String path) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$root$path';
  }

  Future<AppControlResult> check({
    required String appVersion,
    required String deviceId,
    required String platform,
  }) async {
    final res = await apiHttpClient
        .post(
          Uri.parse(_url('/api/app/check')),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'X-App-Platform': platform,
            'X-App-Version': appVersion,
            'X-Device-Id': deviceId,
          },
          body: jsonEncode({
            'app_version': appVersion,
            'device_id': deviceId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录', statusCode: 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = '控制检查失败（${res.statusCode}）';
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['detail'] != null) msg = m['detail'].toString();
      } catch (_) {}
      throw ApiException(msg, statusCode: res.statusCode);
    }
    return AppControlResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
