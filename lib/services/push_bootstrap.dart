import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_nav.dart';
import '../ui/chat_room_screen.dart';
import '../ui/in_app_notifier.dart';
import '../ui/messages_hub_screen.dart';
import 'messages_api.dart';
import 'inbox_service.dart';

/// 后台 FCM 入口（必须顶层函数）。带 notification 载荷时系统会弹通知栏。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 无需自绘；系统托盘由 FCM notification 展示。
}

/// Firebase 初始化 + 真 FCM token 上报。
/// 启动只做短超时探测；登录后在后台用更长超时重试，避免永久卡在 local: 占位。
class PushBootstrap {
  PushBootstrap._();
  static bool _firebaseReady = false;
  static bool _bgHandlerBound = false;
  static StreamSubscription<RemoteMessage>? _fgSub;
  static StreamSubscription<String>? _tokenSub;
  static bool _openedHooked = false;

  static bool get firebaseReady => _firebaseReady;

  static Future<T?> _withTimeout<T>(
    Future<T> future, {
    required Duration timeout,
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

  /// [quick] 启动用短超时；登录后用 [quick]=false 再试一次。
  static Future<void> ensureInitialized({bool quick = true}) async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (_firebaseReady) return;

    final timeout =
        quick ? const Duration(seconds: 4) : const Duration(seconds: 15);
    try {
      if (Firebase.apps.isEmpty) {
        await _withTimeout(
          Firebase.initializeApp(),
          timeout: timeout,
          label: 'initializeApp',
        );
      }
      if (Firebase.apps.isEmpty) {
        _firebaseReady = false;
        return;
      }
      if (!_bgHandlerBound) {
        try {
          FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler,
          );
          _bgHandlerBound = true;
        } catch (_) {}
      }
      _firebaseReady = true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Firebase init skipped: $e');
      }
      _firebaseReady = false;
    }
  }

  static Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return;
      await Permission.notification
          .request()
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// 登录后调用：尽量拿到真 token；失败时若 Firebase 已就绪则不上报 local:（避免覆盖）。
  static Future<String?> registerToken({
    required MessagesApi api,
    required String platform,
    required InboxService inbox,
  }) async {
    await ensureInitialized(quick: false);
    await _ensureNotificationPermission();

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
          timeout: const Duration(seconds: 8),
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

        // 多试几次：冷启动 + 弱网时 getToken 经常偏慢
        for (var i = 0; i < 3 && (fcmToken == null || fcmToken.isEmpty); i++) {
          fcmToken = await _withTimeout<String?>(
            messaging.getToken(),
            timeout: Duration(seconds: 12 + i * 4),
            label: 'getToken#$i',
          );
          if (fcmToken == null || fcmToken.isEmpty) {
            await Future<void>.delayed(Duration(milliseconds: 600 * (i + 1)));
          }
        }

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

    // Firebase 已就绪却拿不到 token：不要用 local: 覆盖（否则系统推送永远发不出去）
    if (_firebaseReady && (fcmToken == null || fcmToken.isEmpty)) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('FCM: firebase ready but no token yet; skip local upsert');
      }
      return null;
    }

    try {
      await inbox
          .registerPushChannel(
            api: api,
            platform: platform,
            fcmToken: fcmToken,
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    return fcmToken;
  }

  static void _onForegroundMessage(RemoteMessage message) {
    // 前台：系统通知栏通常不展示 notification 载荷，改走软件内横幅
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
