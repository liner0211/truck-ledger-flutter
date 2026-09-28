import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_nav.dart';
import '../services/app_control_api.dart';
import '../services/auth_api.dart';
import '../services/device_id_service.dart';
import '../services/devices_api.dart';
import '../services/feature_flags.dart';
import '../services/inbox_service.dart';
import '../services/messages_api.dart';
import '../services/realtime_socket.dart';
import '../services/sync_service.dart';
import '../ui/in_app_notifier.dart';
import '../ui/message_detail_screen.dart';
import '../ui/messages_screen.dart';
import '../ui/support_chat_screen.dart';

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
  int get unreadMessages => _unreadMessages;
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
      if (type == 'inbox' || type == 'support') {
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
      InAppNotifier.instance.show(
        title: title,
        body: body.isEmpty ? null : body,
        onTap: () {
          if (mid != null && mid > 0) {
            AppNav.push(
              MaterialPageRoute<void>(
                builder: (_) => MessageDetailScreen(messageId: mid),
              ),
            );
          } else {
            AppNav.push(
              MaterialPageRoute<void>(
                builder: (_) => const MessagesScreen(),
              ),
            );
          }
        },
      );
      return;
    }
    if (type == 'support') {
      if (event != 'message') return;
      if (e['sender_role'] == 'user') return;
      InAppNotifier.instance.show(
        title: '客服新消息',
        body: (e['preview'] as String?) ?? '管理员回复了你',
        onTap: () {
          AppNav.push(
            MaterialPageRoute<void>(
              builder: (_) => const SupportChatScreen(),
            ),
          );
        },
      );
    }
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
      _unreadMessages = await inbox.refresh(api);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> bootstrapPushAndInbox() async {
    final api = messagesApi;
    if (api == null) return;
    await inbox.registerPushChannel(api: api, platform: platformName);
    await refreshInbox();
    _connectRealtime();
  }

  Future<void> setLocalRevision(int rev) async {
    _localRevision = rev;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(localRevisionKey, rev);
    notifyListeners();
  }
}
