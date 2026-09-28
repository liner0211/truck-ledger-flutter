import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api.dart';
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
    realtime.connect(baseUrl: api.baseUrl, token: t);
    _rtSub = realtime.events.listen((e) {
      final type = e['type'];
      if (type == 'inbox' || type == 'support') {
        realtimeTick++;
        notifyListeners();
      }
    });
  }

  Future<void> _persist() async {
    await prefs.setString('admin_base_url', api.baseUrl);
    await prefs.setString('admin_token', api.token ?? '');
    await prefs.setInt('admin_id', admin?.id ?? 0);
    await prefs.setString('admin_username', admin?.username ?? '');
    await prefs.setString('admin_role', admin?.role ?? '');
    await prefs.setStringList('admin_perms', admin?.permissions ?? []);
  }
}
