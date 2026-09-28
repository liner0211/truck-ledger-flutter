import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_nav.dart';
import '../services/app_control_api.dart';
import '../services/auth_api.dart';
import '../services/device_id_service.dart';
import '../services/china_push_bootstrap.dart';
import '../services/chat_api.dart';
import '../services/devices_api.dart';
import '../services/feature_flags.dart';
import '../services/inbox_service.dart';
import '../services/local_push_service.dart';
import '../services/messages_api.dart';
import '../services/push_bootstrap.dart';
import '../services/realtime_socket.dart';
import '../services/sync_service.dart';
import '../ui/chat_room_screen.dart';
import '../ui/in_app_notifier.dart';
import '../ui/message_detail_screen.dart';
import '../ui/messages_hub_screen.dart';

class AuthController extends ChangeNotifier {
  static const serverUrlKey = 'TruckLedger.serverUrl';
  static const tokenKey = 'TruckLedger.authToken';
  static const usernameKey = 'TruckLedger.username';
  static const userIdKey = 'TruckLedger.userId';
  static const licensePlateKey = 'TruckLedger.licensePlate';
  static const savedLoginUsernameKey = 'TruckLedger.savedLoginUsername';
  static const savedLoginPasswordKey = 'TruckLedger.savedLoginPassword';
  static const localUpdatedAtKey = 'TruckLedger.localUpdatedAt';
  static const remoteUpdatedAtKey = 'TruckLedger.remoteUpdatedAt';
  static const localRevisionKey = 'TruckLedger.localRevision';
  static const lastControlOkAtKey = 'TruckLedger.lastControlOkAt';

  /// 发行版内置云端入口。Release UI 不展示该地址；仅 Debug/Profile 可改。
  static const defaultServerUrl = 'https://truck.liner0211.online';

  String _serverUrl = defaultServerUrl;
  String? _token;
  String? _username;
  int? _userId;
  String? _licensePlate;
  UserProfile? _profile;
  AppControlResult? _lastControl;
  bool _initialized = false;
  int _localRevision = 0;
  int _unreadMessages = 0;
  int _unreadSupport = 0;
  int _unreadChatDm = 0;
  int _unreadChatGroup = 0;
  final Set<int> _knownMessageIds = {};
  Timer? _fgPoll;
  FeatureFlags _featureFlags = FeatureFlags();

  String get serverUrl => _serverUrl;
  String? get token => _token;
  String? get username => _username;
  int? get userId => _userId;
  String? get licensePlate => _licensePlate;
  UserProfile? get profile => _profile;
  AppControlResult? get lastControl => _lastControl;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isInitialized => _initialized;
  int get localRevision => _localRevision;
  /// 站内信 + 客服 + 聊天未读合计（红点数量）
  int get unreadMessages =>
      _unreadMessages + _unreadSupport + _unreadChatDm + _unreadChatGroup;
  int get unreadInbox => _unreadMessages;
  int get unreadSupport => _unreadSupport;
  int get unreadChat => _unreadChatDm + _unreadChatGroup;
  FeatureFlags get featureFlags => _featureFlags;
  bool get writeAllowed => _profile?.writeAllowed ?? true;

  final InboxService inbox = InboxService();
  final RealtimeSocket realtime = RealtimeSocket();
  StreamSubscription? _rtSub;

  /// WebSocket 事件流（inbox / support），供消息页订阅刷新。
  Stream<Map<String, dynamic>> get realtimeEvents => realtime.events;

  AuthApi get api => AuthApi(baseUrl: _serverUrl);

  SyncService? get syncService {
    final t = _token;
    if (t == null || t.isEmpty) return null;
    return SyncService(baseUrl: _serverUrl, token: t);
  }

  AppControlApi? get controlApi {
    final t = _token;
    if (t == null || t.isEmpty) return null;
    return AppControlApi(baseUrl: _serverUrl, token: t);
  }

  MessagesApi? get messagesApi {
    final t = _token;
    if (t == null || t.isEmpty) return null;
    return MessagesApi(baseUrl: _serverUrl, token: t);
  }

  ChatApi? get chatApi {
    final t = _token;
    if (t == null || t.isEmpty) return null;
    return ChatApi(baseUrl: _serverUrl, token: t);
  }

  DevicesApi? get devicesApi {
    final t = _token;
    if (t == null || t.isEmpty) return null;
    return DevicesApi(baseUrl: _serverUrl, token: t);
  }

  String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(serverUrlKey) ?? defaultServerUrl;
    _token = prefs.getString(tokenKey);
    _username = prefs.getString(usernameKey);
    _userId = prefs.getInt(userIdKey);
    _licensePlate = prefs.getString(licensePlateKey);
    _localRevision = prefs.getInt(localRevisionKey) ?? 0;
    // 清除历史明文密码
    if (prefs.containsKey(savedLoginPasswordKey)) {
      await prefs.remove(savedLoginPasswordKey);
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _serverUrl = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(serverUrlKey, trimmed);
    notifyListeners();
  }

  Future<void> _saveSession(AuthResult result) async {
    _token = result.token;
    _username = result.username;
    _userId = result.userId;
    _profile = result.profile;
    if (result.licensePlate != null && result.licensePlate!.isNotEmpty) {
      _licensePlate = result.licensePlate;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, result.token);
    await prefs.setString(usernameKey, result.username);
    await prefs.setInt(userIdKey, result.userId);
    if (_licensePlate != null && _licensePlate!.isNotEmpty) {
      await prefs.setString(licensePlateKey, _licensePlate!);
    }
    notifyListeners();
  }

  Future<void> saveLoginUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(savedLoginUsernameKey, username);
  }

  Future<String?> readSavedLoginUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(savedLoginUsernameKey);
  }

  @Deprecated('明文密码已禁用')
  Future<void> saveLoginCredentials({
    required String username,
    required String password,
  }) async {
    await saveLoginUsername(username);
  }

  @Deprecated('明文密码已禁用')
  Future<({String? username, String? password})> readSavedLoginCredentials() async {
    return (username: await readSavedLoginUsername(), password: null);
  }

  Future<void> register({
    required String username,
    required String password,
    required String licensePlate,
  }) async {
    final result = await api.register(
      username: username,
      password: password,
      licensePlate: licensePlate,
    );
    await _saveSession(result);
    await saveLoginUsername(username);
    _connectRealtime();
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final result = await api.login(username: username, password: password);
    await _saveSession(result);
    await saveLoginUsername(username);
    _connectRealtime();
  }

  Future<void> refreshProfile() async {
    final t = _token;
    if (t == null) return;
    try {
      _profile = await api.me(t);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode == 401) await logout();
      rethrow;
    }
  }

  Future<AppControlResult?> runControlCheck(String appVersion) async {
    final api = controlApi;
    if (api == null) return null;
    final deviceId = await DeviceIdService.getOrCreate();
    try {
      final result = await api.check(
        appVersion: appVersion,
        deviceId: deviceId,
        platform: platformName,
      );
      _lastControl = result;
      _featureFlags = result.featureFlags;
      if (result.account != null) {
        _profile = result.account;
      }
      if (result.allowed) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          lastControlOkAtKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      notifyListeners();
      return result;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await logout();
      }
      rethrow;
    }
  }

  Future<bool> isWithinOfflineGrace() async {
    final grace = _lastControl?.offlineGraceSec ?? 259200;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(lastControlOkAtKey) ?? 0;
    if (last <= 0) return false;
    final elapsed = (DateTime.now().millisecondsSinceEpoch - last) ~/ 1000;
    return elapsed <= grace;
  }

  Future<void> logout() async {
    _rtSub?.cancel();
    _rtSub = null;
    realtime.connectionState.removeListener(_onRtConnChanged);
    realtime.disconnect();
    _token = null;
    _username = null;
    _userId = null;
    _licensePlate = null;
    _profile = null;
    _lastControl = null;
    _unreadMessages = 0;
    _unreadSupport = 0;
    _unreadChatDm = 0;
    _unreadChatGroup = 0;
    _knownMessageIds.clear();
    _stopFgPoll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
    await prefs.remove(usernameKey);
    await prefs.remove(userIdKey);
    await prefs.remove(licensePlateKey);
    notifyListeners();
  }

  void _connectRealtime() {
    final t = _token;
    if (t == null || t.isEmpty) return;
    _rtSub?.cancel();
    realtime.connectionState.removeListener(_onRtConnChanged);
    realtime.connect(baseUrl: _serverUrl, token: t);
    realtime.connectionState.addListener(_onRtConnChanged);
    _rtSub = realtime.events.listen((e) {
      final type = e['type']?.toString();
      if (type == 'inbox' || type == 'support' || type == 'chat') {
        refreshInbox();
        _maybeShowInAppNotice(e);
      }
    });
  }

  void _maybeShowInAppNotice(Map<String, dynamic> e) {
    final type = e['type']?.toString();
    final event = e['event']?.toString() ?? '';
    if (type == 'inbox') {
      if (event != 'created' && event != 'reply') return;
      if (event == 'reply' && e['sender_role'] == 'user') return;
      final mid = (e['message_id'] as num?)?.toInt();
      final title = (e['title'] as String?)?.trim().isNotEmpty == true
          ? (e['title'] as String)
          : (event == 'reply' ? '消息有新回复' : '新站内信');
      final body = (e['preview'] as String?) ?? '';
      final payload =
          (mid != null && mid > 0) ? 'inbox:$mid' : 'hub:0';
      _notifyUser(title: title, body: body, payload: payload, onTap: () {
        if (mid != null && mid > 0) {
          AppNav.push(
            MaterialPageRoute<void>(
              builder: (_) => MessageDetailScreen(messageId: mid),
            ),
          );
        } else {
          AppNav.push(
            MaterialPageRoute<void>(
              builder: (_) => const MessagesHubScreen(initialTab: 0),
            ),
          );
        }
      });
      return;
    }
    if (type == 'support') {
      if (event != 'message') return;
      if (e['sender_role'] == 'user') return;
      _notifyUser(
        title: '客服新消息',
        body: (e['preview'] as String?) ?? '管理员回复了你',
        payload: 'support',
        onTap: () {
          AppNav.push(
            MaterialPageRoute<void>(
              builder: (_) => const MessagesHubScreen(initialTab: 1),
            ),
          );
        },
      );
      return;
    }
    if (type == 'chat') {
      if (event != 'message') return;
      final sid = (e['sender_user_id'] as num?)?.toInt();
      if (sid != null && sid == _userId) return;
      final cid = (e['conversation_id'] as num?)?.toInt() ?? 0;
      final who = (e['sender_username'] as String?)?.trim();
      final title = who != null && who.isNotEmpty ? who : '新聊天消息';
      final body = (e['preview'] as String?) ?? '';
      final payload = cid > 0 ? 'chat:$cid' : 'hub:2';
      _notifyUser(
        title: title,
        body: body,
        payload: payload,
        onTap: () {
          if (cid > 0) {
            AppNav.push(
              MaterialPageRoute<void>(
                builder: (_) => ChatRoomScreen(
                  conversationId: cid,
                  title: who ?? '聊天',
                ),
              ),
            );
          } else {
            AppNav.push(
              MaterialPageRoute<void>(
                builder: (_) => const MessagesHubScreen(initialTab: 2),
              ),
            );
          }
        },
      );
    }
  }

  /// 前台横幅 + 系统通知栏（可点开跳转）。不依赖 Google。
  void _notifyUser({
    required String title,
    String? body,
    required String payload,
    required VoidCallback onTap,
  }) {
    InAppNotifier.instance.show(
      title: title,
      body: body == null || body.isEmpty ? null : body,
      onTap: onTap,
    );
    unawaited(
      LocalPushService.instance.show(
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }

  void _onRtConnChanged() => notifyListeners();

  Future<int> readLocalUpdatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(localUpdatedAtKey) ?? 0;
  }

  Future<int> readRemoteUpdatedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(remoteUpdatedAtKey) ?? 0;
  }

  Future<void> setLocalUpdatedAt(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(localUpdatedAtKey, ms);
  }

  Future<void> setRemoteUpdatedAt(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(remoteUpdatedAtKey, ms);
  }

  Future<void> refreshInbox() async {
    final api = messagesApi;
    if (api == null) return;
    try {
      final r = await inbox.refresh(api);
      _unreadMessages = r.unread;
      _unreadSupport = r.supportUnread;
      _unreadChatDm = r.chatDm;
      _unreadChatGroup = r.chatGroup;
      for (final m in inbox.latest) {
        _knownMessageIds.add(m.id);
      }
      notifyListeners();
    } catch (_) {}
  }

  /// 回到前台 / 定时：轮询补拉，并对漏掉的新消息弹软件内通知。
  Future<void> pollInboxOnForeground({bool notifyMissed = true}) async {
    final api = messagesApi;
    if (api == null || !isLoggedIn) return;

    final prevIds = Set<int>.from(_knownMessageIds);
    final prevTotal = unreadMessages;
    final prevSupport = _unreadSupport;
    final prevChat = unreadChat;

    try {
      final r = await inbox.refresh(api);
      _unreadMessages = r.unread;
      _unreadSupport = r.supportUnread;
      _unreadChatDm = r.chatDm;
      _unreadChatGroup = r.chatGroup;
      notifyListeners();

      if (realtime.connectionState.value != RealtimeConnState.online) {
        _connectRealtime();
      }

      if (!notifyMissed) {
        for (final m in inbox.latest) {
          _knownMessageIds.add(m.id);
        }
        return;
      }

      final fresh = inbox.latest
          .where((m) => !m.isRead && !prevIds.contains(m.id))
          .toList();
      for (final m in inbox.latest) {
        _knownMessageIds.add(m.id);
      }

      if (fresh.isNotEmpty) {
        final first = fresh.first;
        final more = fresh.length - 1;
        _notifyUser(
          title: first.title.isNotEmpty ? first.title : '新站内信',
          body: more > 0
              ? '${first.body}\n还有 $more 条未读'
              : (first.body.isEmpty ? null : first.body),
          payload: 'inbox:${first.id}',
          onTap: () {
            AppNav.push(
              MaterialPageRoute<void>(
                builder: (_) => MessageDetailScreen(messageId: first.id),
              ),
            );
          },
        );
      } else if (_unreadSupport > prevSupport && _unreadSupport > 0) {
        _notifyUser(
          title: '客服新消息',
          body: '有 $_unreadSupport 条未读客服消息',
          payload: 'support',
          onTap: () {
            AppNav.push(
              MaterialPageRoute<void>(
                builder: (_) => const MessagesHubScreen(initialTab: 1),
              ),
            );
          },
        );
      } else if (unreadChat > prevChat && unreadChat > 0) {
        _notifyUser(
          title: '聊天未读',
          body: '有 $unreadChat 条聊天未读',
          payload: 'hub:2',
          onTap: () {
            AppNav.push(
              MaterialPageRoute<void>(
                builder: (_) => const MessagesHubScreen(initialTab: 2),
              ),
            );
          },
        );
      } else if (unreadMessages > prevTotal && unreadMessages > 0) {
        _notifyUser(
          title: '未读消息',
          body: '您有 $unreadMessages 条未读',
          payload: 'hub:0',
          onTap: () {
            AppNav.push(
              MaterialPageRoute<void>(
                builder: (_) => const MessagesHubScreen(),
              ),
            );
          },
        );
      }
    } catch (_) {
      if (realtime.connectionState.value != RealtimeConnState.online) {
        _connectRealtime();
      }
    }
  }

  void startForegroundPolling() {
    _stopFgPoll();
    _fgPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!isLoggedIn) return;
      // 在线时轻度轮询；WS 离线时更依赖轮询
      unawaited(pollInboxOnForeground(notifyMissed: true));
    });
  }

  void _stopFgPoll() {
    _fgPoll?.cancel();
    _fgPoll = null;
  }

  Future<void> bootstrapPushAndInbox() async {
    final api = messagesApi;
    if (api == null) return;
    try {
      await refreshInbox().timeout(const Duration(seconds: 10));
    } catch (_) {}
    _connectRealtime();
    startForegroundPolling();
    // 国内推送优先极光；FCM 可选（无 Google 时自然失败）
    unawaited(() async {
      try {
        await ChinaPushBootstrap.registerIfConfigured(
          api: api,
          inbox: inbox,
          platform: platformName,
          jpushAppKey: _lastControl?.jpushAppKey,
          production: true,
        ).timeout(const Duration(seconds: 25));
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('bootstrap JPush skipped: $e');
        }
      }
      try {
        await PushBootstrap.registerToken(
          api: api,
          platform: platformName,
          inbox: inbox,
        ).timeout(const Duration(seconds: 15));
      } catch (_) {}
    }());
  }

  Future<void> setLocalRevision(int rev) async {
    _localRevision = rev;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(localRevisionKey, rev);
    notifyListeners();
  }
}
