import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api.dart';
import 'in_app_notifier.dart';
import 'realtime_socket.dart';

class AdminSession extends ChangeNotifier {
  AdminSession(this.prefs);
  final SharedPreferences prefs;

  final api = AdminApi(baseUrl: AdminApi.defaultBaseUrl());
  final realtime = RealtimeSocket();
  StreamSubscription? _rtSub;
  AdminProfile? admin;
  String? error;
  bool busy = false;
  int realtimeTick = 0;

  /// 通知点击：请求主壳切到消息 Tab（1=站内信管理 2=客服）
  int? pendingMessagesTab;
  int? pendingMessageId;
  int? pendingThreadId;

  bool get isLoggedIn => api.token != null && api.token!.isNotEmpty && admin != null;

  Stream<Map<String, dynamic>> get realtimeEvents => realtime.events;

  Future<void> restore() async {
    final url = prefs.getString('admin_base_url');
    final token = prefs.getString('admin_token');
    final username = prefs.getString('admin_username');
    final role = prefs.getString('admin_role');
    final perms = prefs.getStringList('admin_perms');
    if (url != null && url.isNotEmpty) api.baseUrl = url;
    if (token != null && token.isNotEmpty && username != null && role != null) {
      api.token = token;
      admin = AdminProfile(
        id: prefs.getInt('admin_id') ?? 0,
        username: username,
        role: role,
        permissions: perms ?? const [],
      );
      notifyListeners();
      try {
        final me = await api.me();
        admin = me;
        await _persist();
        _connectRealtime();
        notifyListeners();
      } catch (_) {
        await logout();
      }
    }
  }

  Future<void> login(String username, String password, {String? baseUrl}) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (baseUrl != null && baseUrl.trim().isNotEmpty) {
        api.baseUrl = baseUrl.trim();
      }
      final r = await api.login(username.trim(), password);
      admin = r.admin;
      await prefs.setString('admin_last_login_user', username.trim());
      await _persist();
      _connectRealtime();
    } catch (e) {
      error = '$e';
      admin = null;
      api.token = null;
      realtime.disconnect();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _rtSub?.cancel();
    _rtSub = null;
    realtime.connectionState.removeListener(_onRtConnChanged);
    realtime.disconnect();
    api.token = null;
    admin = null;
    await prefs.remove('admin_token');
    await prefs.remove('admin_username');
    await prefs.remove('admin_role');
    await prefs.remove('admin_perms');
    await prefs.remove('admin_id');
    notifyListeners();
  }

  void _connectRealtime() {
    final t = api.token;
    if (t == null || t.isEmpty) return;
    _rtSub?.cancel();
    realtime.connectionState.removeListener(_onRtConnChanged);
    realtime.connect(baseUrl: api.baseUrl, token: t);
    realtime.connectionState.addListener(_onRtConnChanged);
    _rtSub = realtime.events.listen((e) {
      final type = e['type']?.toString();
      if (type == 'inbox' || type == 'support') {
        realtimeTick++;
        notifyListeners();
        _maybeShowInAppNotice(e);
      }
    });
  }

  void clearPendingNav() {
    pendingMessagesTab = null;
    pendingMessageId = null;
    pendingThreadId = null;
  }

  void _maybeShowInAppNotice(Map<String, dynamic> e) {
    final type = e['type']?.toString();
    final event = e['event']?.toString() ?? '';
    if (type == 'inbox') {
      // 已读实时刷新列表即可，不弹通知
      if (event == 'read' || event == 'read_all' || event == 'deleted') return;
      if (event == 'reply' && e['sender_role'] == 'admin') return;
      if (event == 'created') return; // 管理员自己发出的站内信
      final mid = (e['message_id'] as num?)?.toInt();
      final title = event == 'reply' ? '用户回复了站内信' : '站内信更新';
      final body = (e['preview'] as String?) ?? (e['title'] as String?) ?? '';
      InAppNotifier.instance.show(
        title: title,
        body: body.isEmpty ? null : body,
        onTap: () {
          pendingMessagesTab = 1;
          pendingMessageId = mid;
          pendingThreadId = null;
          notifyListeners();
        },
      );
      return;
    }
    if (type == 'support') {
      if (event == 'read') return;
      if (event != 'message') return;
      if (e['sender_role'] == 'admin') return;
      final tid = (e['thread_id'] as num?)?.toInt();
      final who = (e['username'] as String?)?.trim();
      InAppNotifier.instance.show(
        title: who != null && who.isNotEmpty ? '$who 发来客服消息' : '新的客服消息',
        body: (e['preview'] as String?) ?? '',
        onTap: () {
          pendingMessagesTab = 2;
          pendingThreadId = tid;
          pendingMessageId = null;
          notifyListeners();
        },
      );
    }
  }

  void _onRtConnChanged() => notifyListeners();

  Future<void> _persist() async {
    await prefs.setString('admin_base_url', api.baseUrl);
    await prefs.setString('admin_token', api.token ?? '');
    await prefs.setInt('admin_id', admin?.id ?? 0);
    await prefs.setString('admin_username', admin?.username ?? '');
    await prefs.setString('admin_role', admin?.role ?? '');
    await prefs.setStringList('admin_perms', admin?.permissions ?? []);
  }
}
