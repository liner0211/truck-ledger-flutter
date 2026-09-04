import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_http_client.dart';
import '../services/auth_api.dart';
import '../services/network_access_helper.dart';
import '../state/auth_controller.dart';
import '../state/ledger_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _licensePlate = TextEditingController();
  final _serverUrl = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  bool _obscure = true;
  bool _credentialsLoaded = false;
  String? _error;
  int? _trialDays;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serverUrl.text.isEmpty) {
      _serverUrl.text = context.read<AuthController>().serverUrl;
    }
    if (!_credentialsLoaded) {
      _credentialsLoaded = true;
      _loadSavedCredentials();
      _loadPublicConfig();
    }
  }

  Future<void> _loadPublicConfig() async {
    final base = context.read<AuthController>().serverUrl;
    final days = await _fetchTrialDays(base);
    if (!mounted) return;
    setState(() => _trialDays = days);
  }

  Future<int?> _fetchTrialDays(String baseUrl) async {
    try {
      final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final res = await apiHttpClient
          .get(Uri.parse('$root/api/auth/config'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      return (m['trial_days'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSavedCredentials() async {
    final username = await context.read<AuthController>().readSavedLoginUsername();
    if (!mounted) return;
    if (username != null && username.isNotEmpty) {
      _username.text = username;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _licensePlate.dispose();
    _serverUrl.dispose();
    super.dispose();
  }

  String? _normalizeLicensePlate(String raw) {
    final p = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s·.]'), '');
    if (p.length < 5 || p.length > 10) return null;
    if (!RegExp(r'^[\u4e00-\u9fa5]').hasMatch(p)) return null;
    if (!RegExp(r'^[\u4e00-\u9fa5A-Z0-9]+$').hasMatch(p)) return null;
    return p;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = context.read<AuthController>();
    final username = _username.text.trim();
    final password = _password.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _busy = false;
        _error = '请填写用户名和密码';
      });
      return;
    }

    String? licensePlate;
    if (_registerMode) {
      licensePlate = _normalizeLicensePlate(_licensePlate.text);
      if (licensePlate == null) {
        setState(() {
          _busy = false;
          _error = '请填写有效车牌号（5–10 位，含省份汉字，如 京A12345）';
        });
        return;
      }
    }

    try {
      final offline = await NetworkAccessHelper.checkBeforeRequest();
      if (offline != null) {
        setState(() {
          _busy = false;
          _error = offline;
        });
        return;
      }

      if (!kReleaseMode) {
        await auth.setServerUrl(_serverUrl.text);
      }
      await auth.api.checkHealth();
      if (_registerMode) {
        await auth.register(
          username: username,
          password: password,
          licensePlate: licensePlate!,
        );
      } else {
        await auth.login(username: username, password: password);
      }

      if (!mounted) return;
      final ledger = context.read<LedgerController>();
      if (ledger.book.rounds.isEmpty) {
        final msg = await ledger.pullFromCloud();
        if (mounted && msg != '已从云端拉取（0 个圈次）') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = NetworkAccessHelper.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.local_shipping, size: 56, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    '卡车记账',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _registerMode
                        ? (_trialDays != null && _trialDays! > 0
                            ? '注册后赠送 $_trialDays 天试用，可同步云端账本'
                            : '注册新账号并同步账本')
                        : '登录以同步云端账本',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 28),
                  // 发行版不向最终用户展示 API 域名；仅 Debug/Profile 可改地址便于联调。
                  if (!kReleaseMode) ...[
                    TextField(
                      controller: _serverUrl,
                      decoration: const InputDecoration(
                        labelText: '服务器地址（仅调试）',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.cloud_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                  ),
                  if (_registerMode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _licensePlate,
                      decoration: const InputDecoration(
                        labelText: '车牌号',
                        hintText: '如 京A12345',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: cs.error, height: 1.35),
                    ),
                    TextButton(
                      onPressed: _busy ? null : NetworkAccessHelper.openAppNetworkSettings,
                      child: const Text('打开应用联网设置'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_registerMode ? '注册并登录' : '登录'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _registerMode = !_registerMode;
                              _error = null;
                            }),
                    child: Text(_registerMode ? '已有账号？去登录' : '没有账号？注册'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '网络权限：Android 安装时已自动授予，不会出现授权弹窗。\n'
                    '相册权限：首次打开应用时会弹出系统授权框。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
