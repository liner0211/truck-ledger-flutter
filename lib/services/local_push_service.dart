import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_nav.dart';
import '../ui/chat_room_screen.dart';
import '../ui/messages_hub_screen.dart';
import '../ui/message_detail_screen.dart';

/// 系统通知栏（不依赖 Google）。
/// - 前台：不弹系统横幅（由 InAppNotifier 负责），避免 iOS「前台才弹」的错觉
/// - 后台：弹出通知栏；iOS 杀进程后需极光/APNs 才能继续收到
class LocalPushService with WidgetsBindingObserver {
  LocalPushService._();
  static final LocalPushService instance = LocalPushService._();

  static const _channelId = 'messages';
  static const _channelName = '消息';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _observing = false;
  bool _inForeground = true;
  int _nid = 1000;

  bool get inForeground => _inForeground;

  Future<void> init() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (_ready) return;

    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      _inForeground =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
              WidgetsBinding.instance.lifecycleState == null;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onResponse,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: '站内信、客服与聊天',
          importance: Importance.high,
        ),
      );
    }
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    try {
      await Permission.notification.request();
    } catch (_) {}

    _ready = true;

    final launch = await _plugin.getNotificationAppLaunchDetails();
    final resp = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && resp?.payload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openPayload(resp!.payload!);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
  }

  void _onResponse(NotificationResponse response) {
    final p = response.payload;
    if (p == null || p.isEmpty) return;
    openPayload(p);
  }

  /// payload：`inbox:123` / `support` / `chat:456` / `hub:0`
  static void openPayload(String payload) {
    final parts = payload.split(':');
    final type = parts.isNotEmpty ? parts[0] : 'hub';
    final id = parts.length > 1 ? int.tryParse(parts[1]) : null;

    if (type == 'inbox' && id != null && id > 0) {
      AppNav.push(
        MaterialPageRoute<void>(
          builder: (_) => MessageDetailScreen(messageId: id),
        ),
      );
      return;
    }
    if (type == 'chat' && id != null && id > 0) {
      AppNav.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(conversationId: id, title: '聊天'),
        ),
      );
      return;
    }
    final tab = switch (type) {
      'support' => 1,
      'chat' => 2,
      'hub' => (id ?? 0).clamp(0, 2),
      _ => 0,
    };
    AppNav.push(
      MaterialPageRoute<void>(
        builder: (_) => MessagesHubScreen(initialTab: tab),
      ),
    );
  }

  /// [force] 为 true 时前台也写通知栏（一般不用）。
  Future<void> show({
    required String title,
    String? body,
    required String payload,
    bool force = false,
  }) async {
    if (!_ready) {
      await init();
    }
    if (!_ready) return;

    // iOS/Android：前台只走软件内横幅，避免「回前台才看到通知」被当成前台系统弹窗
    if (!force && _inForeground) {
      return;
    }

    final id = _nid++;
    final text = body ?? '';
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '站内信、客服与聊天',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      styleInformation: BigTextStyleInformation(text.isEmpty ? title : text),
    );
    // 后台展示；若因时序误在前台调用，iOS 也不再弹横幅（由 InApp 负责）
    final iosDetails = DarwinNotificationDetails(
      presentAlert: !_inForeground || force,
      presentBadge: true,
      presentSound: !_inForeground || force,
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails:
          NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }
}
