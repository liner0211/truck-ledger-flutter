import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_api.dart';
import '../admin_session.dart';
import '../ui/admin_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _user;
  final _pass = TextEditingController();
  final _url = TextEditingController(text: AdminApi.defaultBaseUrl());
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _user = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final last = context.read<AdminSession>().prefs.getString('admin_last_login_user') ?? '';
      if (last.isNotEmpty) _user.text = last;
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AdminSession>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.45),
                    cs.surface,
                    cs.secondaryContainer.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: const SafeArea(child: ThemeModeMenuButton()),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 0,
                  color: cs.surface.withValues(alpha: 0.96),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '卡车记账',
                          style: tt.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '管理端',
                          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '用户运营 · 控制面 · 账本协助',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                        TextField(
                          controller: _user,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _pass,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '密码',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) => _submit(s),
                        ),
                        if (!kReleaseMode) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => setState(() => _advanced = !_advanced),
                            icon: Icon(_advanced ? Icons.expand_less : Icons.expand_more),
                            label: Text(_advanced ? '收起高级选项' : '高级选项（服务器地址）'),
                          ),
                          if (_advanced) ...[
                            TextField(
                              controller: _url,
                              decoration: const InputDecoration(
                                labelText: '服务器地址（仅调试）',
                                helperText: '发行版不会展示此字段',
                              ),
                            ),
                          ],
                        ],
                        if (s.error != null) ...[
                          const SizedBox(height: 12),
                          Text(s.error!, style: TextStyle(color: cs.error)),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: s.busy ? null : () => _submit(s),
                          child: s.busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('登录'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(AdminSession s) async {
    await s.login(
      _user.text,
      _pass.text,
      baseUrl: kReleaseMode ? null : _url.text,
    );
  }
}
