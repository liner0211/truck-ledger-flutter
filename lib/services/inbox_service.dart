import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_id_service.dart';
import 'messages_api.dart';

/// 消息未读数 + 推送 Token 上报（无 Firebase 时上报 local 占位 Token，便于服务端登记设备）。
class InboxService {
  static const _lastSeenUnreadKey = 'TruckLedger.lastSeenUnread';

  int unread = 0;
  int supportUnread = 0;
  List<InboxMessage> latest = [];

  Future<({int unread, int supportUnread})> refresh(MessagesApi api) async {
    final r = await api.list();
    unread = r.unread;
    supportUnread = r.supportUnread;
    latest = r.messages;
    return (unread: unread, supportUnread: supportUnread);
  }

  /// 登记推送通道。未集成 FCM 时使用 `local:<deviceId>`，Admin 广播仍走站内信。
  Future<void> registerPushChannel({
    required MessagesApi api,
    required String platform,
    String? fcmToken,
  }) async {
    final deviceId = await DeviceIdService.getOrCreate();
    final token = (fcmToken != null && fcmToken.isNotEmpty)
        ? fcmToken
        : 'local:$deviceId';
    try {
      await api.registerPushToken(
        deviceId: deviceId,
        token: token,
        platform: platform,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('push token register skipped: $e');
      }
    }
  }

  Future<void> rememberUnread(int n) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenUnreadKey, n);
  }
}
