import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:jpush_flutter/jpush_flutter.dart';

import 'inbox_service.dart';
import 'local_push_service.dart';
import 'messages_api.dart';

/// 国内推送（极光）：杀进程仍可达。AppKey 从服务端下发；未配置则跳过。
class ChinaPushBootstrap {
  ChinaPushBootstrap._();
  static final _jpush = JPush.newJPush();
  static bool _started = false;
  static String? _lastAppKey;

  static Future<void> registerIfConfigured({
    required MessagesApi api,
    required InboxService inbox,
    required String platform,
    required String? jpushAppKey,
    bool production = true,
  }) async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final key = (jpushAppKey ?? '').trim();
    if (key.isEmpty || key.length < 16) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('JPush skipped: no app key from server');
      }
      return;
    }

    try {
      if (!_started || _lastAppKey != key) {
        _jpush.setup(
          appKey: key,
          channel: 'truck_ledger',
          production: production,
          debug: kDebugMode,
        );
        // 前台也允许系统通知（与 QQ 类似）；本地横幅仍由 InAppNotifier 补充
        _jpush.setUnShowAtTheForeground(unShow: false);
        _jpush.addEventHandler(
          onReceiveNotification: (Map<String, dynamic> message) async {
            // 前台收到极光通知时，再补一条软件内横幅（可选）
            final note = message['alert']?.toString() ??
                message['title']?.toString() ??
                '新消息';
            // 不重复弹本地通知（极光已弹）
            if (kDebugMode) {
              // ignore: avoid_print
              print('JPush onReceiveNotification: $note');
            }
          },
          onOpenNotification: (Map<String, dynamic> message) async {
            final extras = message['extras'];
            String? payload;
            if (extras is Map) {
              payload = extras['payload']?.toString() ??
                  extras['cn.jpush.android.EXTRA']?.toString();
              if (payload == null && extras['cn.jpush.android.EXTRA'] is Map) {
                final m = extras['cn.jpush.android.EXTRA'] as Map;
                payload = m['payload']?.toString();
              }
            }
            payload ??= message['payload']?.toString();
            if (payload != null && payload.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                LocalPushService.openPayload(payload!);
              });
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                LocalPushService.openPayload('hub:0');
              });
            }
          },
          onReceiveMessage: (Map<String, dynamic> message) async {},
        );
        _started = true;
        _lastAppKey = key;
      }

      // registration id 有时稍晚才就绪
      String rid = '';
      for (var i = 0; i < 8; i++) {
        rid = await _jpush.getRegistrationID();
        if (rid.isNotEmpty) break;
        await Future<void>.delayed(Duration(milliseconds: 400 * (i + 1)));
      }
      if (rid.isEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('JPush: empty registration id');
        }
        return;
      }
      await inbox.registerPushChannel(
        api: api,
        platform: platform,
        fcmToken: 'jpush:$rid',
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('JPush registered: ${rid.substring(0, rid.length.clamp(0, 12))}…');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('JPush setup failed: $e');
      }
    }
  }
}
