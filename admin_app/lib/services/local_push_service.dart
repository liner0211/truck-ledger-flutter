import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// 管理端系统通知栏（不依赖 Google）。
/// - 前台：不弹系统横幅（由 InAppNotifier 负责）
/// - 后台：弹出通知栏；点击经 [onOpenPayload] 切到消息页
class LocalPushService with WidgetsBindingObserver {
  LocalPushService._();
  static final LocalPushService instance = LocalPushService._();

  static const _channelId = 'admin_messages';
  static const _channelName = '管理消息';

  /// 由 [AdminSession] 注册：`inbox:123` / `support` / `chat` / `hub:N`
  static void Function(String payload)? onOpenPayload;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _observing = false;
  bool _inForeground = true;
  int _nid = 2000;

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
          description: '站内信回复、客服与用户聊天',
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

  static void openPayload(String payload) {
    onOpenPayload?.call(payload);
  }

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
    if (!force && _inForeground) {
      return;
    }

    final id = _nid++;
    final text = body ?? '';
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '站内信回复、客服与用户聊天',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      styleInformation: BigTextStyleInformation(text.isEmpty ? title : text),
    );
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
