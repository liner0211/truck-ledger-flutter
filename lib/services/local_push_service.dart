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

/// 系统通知栏（不依赖 Google）。进程在线时由 WebSocket 触发；点击可跳转。
class LocalPushService {
  LocalPushService._();
  static final LocalPushService instance = LocalPushService._();

  static const _channelId = 'messages';
  static const _channelName = '消息';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nid = 1000;

  Future<void> init() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (_ready) return;

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
      try {
        await Permission.notification.request();
      } catch (_) {}
    }

    _ready = true;

    // 冷启动：用户从通知栏点进 App
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final resp = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && resp?.payload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openPayload(resp!.payload!);
      });
    }
  }

  void _onResponse(NotificationResponse response) {
    final p = response.payload;
    if (p == null || p.isEmpty) return;
    openPayload(p);
  }

  /// payload 格式：`inbox:123` / `support` / `chat:456` / `hub:0`
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

  Future<void> show({
    required String title,
    String? body,
    required String payload,
  }) async {
    if (!_ready) {
      await init();
    }
    if (!_ready) return;

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
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
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
