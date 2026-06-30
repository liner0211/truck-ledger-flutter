import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_api.dart';
import '../services/sync_service.dart';

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

  static const defaultServerUrl = 'https://truck.liner0211.online';

  String _serverUrl = defaultServerUrl;
  String? _token;
  String? _username;
  int? _userId;
  String? _licensePlate;
  bool _initialized = false;

  String get serverUrl => _serverUrl;
  String? get token => _token;
  String? get username => _username;
  int? get userId => _userId;
  String? get licensePlate => _licensePlate;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isInitialized => _initialized;

  AuthApi get api => AuthApi(baseUrl: _serverUrl);

  SyncService? get syncService {
    final t = _token;
    if (t == null || t.isEmpty) return null;
    return SyncService(baseUrl: _serverUrl, token: t);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(serverUrlKey) ?? defaultServerUrl;
    _token = prefs.getString(tokenKey);
    _username = prefs.getString(usernameKey);
    _userId = prefs.getInt(userIdKey);
    _licensePlate = prefs.getString(licensePlateKey);
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

  Future<void> saveLoginCredentials({
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(savedLoginUsernameKey, username);
    await prefs.setString(savedLoginPasswordKey, password);
  }

  Future<({String? username, String? password})> readSavedLoginCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      username: prefs.getString(savedLoginUsernameKey),
      password: prefs.getString(savedLoginPasswordKey),
    );
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
    await saveLoginCredentials(username: username, password: password);
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final result = await api.login(username: username, password: password);
    await _saveSession(result);
    await saveLoginCredentials(username: username, password: password);
  }

  Future<void> logout() async {
    _token = null;
    _username = null;
    _userId = null;
    _licensePlate = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
    await prefs.remove(usernameKey);
    await prefs.remove(userIdKey);
    await prefs.remove(licensePlateKey);
    notifyListeners();
  }

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
}
