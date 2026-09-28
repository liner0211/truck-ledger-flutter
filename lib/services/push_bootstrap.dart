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

/// 后台 FCM 入口（必须顶层函数）。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 系统托盘由 FCM notification 载荷展示。
}

/// 初始化 Firebase + 上报 FCM token；未配置 / 超时则回退 local 占位。
/// 注意：所有异步调用都有超时，避免卡死启动与 ControlGate。
class PushBootstrap {
  PushBootstrap._();
  static bool _firebaseReady = false;
  static bool _initAttempted = false;
  static StreamSubscription<RemoteMessage>? _fgSub;
  static StreamSubscription<String>? _tokenSub;
  static bool _openedHooked = false;

  static bool get firebaseReady => _firebaseReady;

  static Future<T?> _withTimeout<T>(
    Future<T> future, {
    Duration timeout = const Duration(seconds: 5),
    String label = 'op',
  }) async {
    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      if (kDebugMode) {
        // ignore: avoid_print
        print('FCM $label timed out after ${timeout.inSeconds}s');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('FCM $label failed: $e');
      }
      return null;
    }
  }

  /// 尝试初始化；失败/超时不抛错。
  static Future<void> ensureInitialized() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (_firebaseReady || _initAttempted) return;
    _initAttempted = true;
    try {
      final ok = await _withTimeout(
        Firebase.initializeApp(),
        timeout: const Duration(seconds: 4),
        label: 'initializeApp',
      );
      if (ok == null && Firebase.apps.isEmpty) {
        _firebaseReady = false;
        return;
      }
      // initializeApp 成功或已有 apps
      if (Firebase.apps.isEmpty) {
        _firebaseReady = false;
        return;
      }
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (_) {}
      _firebaseReady = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Firebase init skipped: $e');
      }
      _firebaseReady = false;
    }
  }

  /// 请求权限、取 token、登记；任何一步超时都不阻塞调用方超过约 8 秒。
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
        await _withTimeout(
          messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          ),
          timeout: const Duration(seconds: 6),
          label: 'requestPermission',
        );
        await _withTimeout(
          messaging.setForegroundNotificationPresentationOptions(
            alert: false,
            badge: true,
            sound: false,
          ),
          timeout: const Duration(seconds: 2),
          label: 'foregroundOptions',
        );
        final tokenOrNull = await _withTimeout<String?>(
          messaging.getToken(),
          timeout: const Duration(seconds: 6),
          label: 'getToken',
        );
        fcmToken = tokenOrNull;
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
        if (!_openedHooked) {
          _openedHooked = true;
          FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
        }
        final initial = await _withTimeout(
          messaging.getInitialMessage(),
          timeout: const Duration(seconds: 2),
          label: 'getInitialMessage',
        );
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
    try {
      await inbox
          .registerPushChannel(
            api: api,
            platform: platform,
            fcmToken: fcmToken,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
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
