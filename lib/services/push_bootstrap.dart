import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../ui/chat_room_screen.dart';
import '../ui/in_app_notifier.dart';
import '../ui/messages_hub_screen.dart';
import 'messages_api.dart';
import 'inbox_service.dart';

/// 后台 FCM 入口（必须顶层函数）。仅刷新标记；前台由 [PushBootstrap] 处理横幅。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 系统托盘由 FCM notification 载荷展示；此处无需额外逻辑。
}

/// 初始化 Firebase + 上报 FCM token；未配置 google-services 时回退 local 占位。
class PushBootstrap {
  PushBootstrap._();
  static bool _firebaseReady = false;
  static StreamSubscription<RemoteMessage>? _fgSub;
  static StreamSubscription<String>? _tokenSub;

  static bool get firebaseReady => _firebaseReady;

  /// 尝试初始化；失败不抛错（无 Firebase 配置时走站内信 + WS）。
  static Future<void> ensureInitialized() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (_firebaseReady) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _firebaseReady = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Firebase init skipped: $e');
      }
      _firebaseReady = false;
    }
  }

  /// 请求权限、取 token、登记到服务端，并挂接前台消息 → 软件内横幅（抑制重复系统通知观感）。
  static Future<String?> registerToken({
    required MessagesApi api,
    required String platform,
    required InboxService inbox,
  }) async {
    await ensureInitialized();
    String? fcmToken;
    if (_firebaseReady) {
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        // iOS：前台不弹系统横幅，改走 InAppNotifier，避免叠两层
        await messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );
        fcmToken = await messaging.getToken();
        _tokenSub?.cancel();
        _tokenSub = messaging.onTokenRefresh.listen((t) async {
          if (t.isEmpty) return;
          await inbox.registerPushChannel(
            api: api,
            platform: platform,
            fcmToken: t,
          );
        });
        _fgSub?.cancel();
        _fgSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
        final initial = await messaging.getInitialMessage();
        if (initial != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateFromData(initial.data);
          });
        }
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('FCM token skipped: $e');
        }
        fcmToken = null;
      }
    }
    await inbox.registerPushChannel(
      api: api,
      platform: platform,
      fcmToken: fcmToken,
    );
    return fcmToken;
  }

  static void _onForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        '新消息';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        '';
    InAppNotifier.instance.show(
      title: title,
      body: body.isEmpty ? null : body,
      onTap: () => _navigateFromData(message.data),
    );
  }

  static void _onOpened(RemoteMessage message) {
    _navigateFromData(message.data);
  }

  static void _navigateFromData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final cid = int.tryParse('${data['conversation_id'] ?? ''}');
    if (type == 'chat' && cid != null && cid > 0) {
      AppNav.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(
            conversationId: cid,
            title: data['title']?.toString() ?? '聊天',
          ),
        ),
      );
      return;
    }
    final tab = switch (type) {
      'support' => 1,
      'chat' => 2,
      _ => 0,
    };
    AppNav.push(
      MaterialPageRoute<void>(
        builder: (_) => MessagesHubScreen(initialTab: tab),
      ),
    );
  }
}
