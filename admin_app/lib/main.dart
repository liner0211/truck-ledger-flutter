import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(AdminRoot(prefs: prefs));
}

class AdminRoot extends StatelessWidget {
  const AdminRoot({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminSession(prefs)..restore(),
      child: MaterialApp(
        title: '卡车记账管理端',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20)),
          useMaterial3: true,
        ),
        home: const _Gate(),
      ),
    );
  }
}

class AdminSession extends ChangeNotifier {
  AdminSession(this.prefs);
  final SharedPreferences prefs;

  final api = AdminApi(baseUrl: AdminApi.defaultBaseUrl());
  AdminProfile? admin;
  String? error;
  bool busy = false;

  bool get isLoggedIn => api.token != null && api.token!.isNotEmpty && admin != null;

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
      await _persist();
    } catch (e) {
      error = '$e';
      admin = null;
      api.token = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    api.token = null;
    admin = null;
    await prefs.remove('admin_token');
    await prefs.remove('admin_username');
    await prefs.remove('admin_role');
    await prefs.remove('admin_perms');
    await prefs.remove('admin_id');
    notifyListeners();
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

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AdminSession>();
    if (!s.isLoggedIn) return const LoginPage();
    return const HomeShell();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController(text: 'liner0211');
  final _pass = TextEditingController();
  final _url = TextEditingController(text: AdminApi.defaultBaseUrl());

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
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('卡车记账 · 管理端', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Android / Windows / Linux',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  if (!kReleaseMode) ...[
                    TextField(
                      controller: _url,
                      decoration: const InputDecoration(labelText: '服务器地址（仅调试）'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(labelText: '用户名'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码'),
                    onSubmitted: (_) => _submit(s),
                  ),
                  if (s.error != null) ...[
                    const SizedBox(height: 12),
                    Text(s.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: s.busy ? null : () => _submit(s),
                    child: s.busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AdminSession>();
    final admin = s.admin!;
    final pages = <Widget>[
      const DashboardPage(),
      const UsersPage(),
      const MessagesPage(),
      if (admin.can('control.write')) const ControlPage(),
      if (admin.can('admins.manage')) const OperatorsPage(),
    ];
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), label: Text('总览')),
      const NavigationRailDestination(icon: Icon(Icons.people_outline), label: Text('用户')),
      const NavigationRailDestination(icon: Icon(Icons.mail_outline), label: Text('消息')),
      if (admin.can('control.write'))
        const NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: Text('控制面')),
      if (admin.can('admins.manage'))
        const NavigationRailDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: Text('运营账号')),
    ];
    if (_index >= pages.length) _index = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('管理端 · ${admin.username}（${admin.isSuper ? '超级' : '运营'}）'),
        actions: [
          IconButton(
            tooltip: '退出',
            onPressed: () => s.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _data;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AdminSession>().api.dashboard();
      if (mounted) setState(() { _data = d; _err = null; });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      return Center(child: Text(_err!));
    }
    if (_data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final stats = (_data!['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    final settings = (_data!['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat('用户', '${stats['user_count']}'),
            _stat('圈次', '${stats['round_count']}'),
            _stat('设备', '${stats['device_count']}'),
            _stat('站内信', '${stats['message_count']}'),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: const Text('应用控制面快照'),
            subtitle: Text(
              '状态 ${settings['app_status']} · 最低 ${settings['min_version']} · 最新 ${settings['latest_version']} · 强更 ${settings['force_update']}',
            ),
          ),
        ),
        TextButton(onPressed: _load, child: const Text('刷新')),
      ],
    );
  }

  Widget _stat(String label, String value) => SizedBox(
        width: 140,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          ),
        ),
      );
}

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, dynamic>> _users = [];
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<AdminSession>().api.users();
      if (mounted) setState(() { _users = list; _err = null; });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _act(int id, String action, {Map<String, dynamic>? body}) async {
    final api = context.read<AdminSession>().api;
    try {
      final msg = await api.userAction(id, action, body: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = context.watch<AdminSession>().admin?.can('users.delete') == true;
    if (_err != null) return Center(child: Text(_err!));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _users.length,
        itemBuilder: (ctx, i) {
          final u = _users[i];
          final id = (u['id'] as num).toInt();
          return Card(
            child: ListTile(
              title: Text('${u['username']} · ${u['license_plate'] ?? ''}'),
              subtitle: Text(
                '${u['status']} / ${u['plan']} · 圈次 ${u['round_count']} · rev ${u['revision']}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'extend') {
                    await _act(id, 'extend', body: {'days': 7});
                  } else if (v == 'convert') {
                    await _act(id, 'convert');
                  } else if (v == 'kick') {
                    await _act(id, 'kick');
                  } else if (v == 'disable') {
                    await _act(id, 'disable');
                  } else if (v == 'enable') {
                    await _act(id, 'enable');
                  } else if (v == 'delete' && canDelete) {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('删除用户'),
                        content: Text('确定删除 ${u['username']}？'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      try {
                        final msg = await context.read<AdminSession>().api.deleteUser(id);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                          _load();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    }
                  } else if (v == 'reset') {
                    final ctrl = TextEditingController();
                    final pass = await showDialog<String>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('重置密码'),
                        content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: '新密码')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('确定')),
                        ],
                      ),
                    );
                    if (pass != null && pass.length >= 6) {
                      await _act(id, 'reset-password', body: {'password': pass});
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'extend', child: Text('延期试用 7 天')),
                  const PopupMenuItem(value: 'convert', child: Text('转正式')),
                  const PopupMenuItem(value: 'kick', child: Text('踢下线')),
                  const PopupMenuItem(value: 'enable', child: Text('启用')),
                  const PopupMenuItem(value: 'disable', child: Text('禁用')),
                  const PopupMenuItem(value: 'reset', child: Text('重置密码')),
                  if (canDelete) const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _userId = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _userId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: '标题')),
        TextField(controller: _body, decoration: const InputDecoration(labelText: '内容'), maxLines: 4),
        TextField(
          controller: _userId,
          decoration: const InputDecoration(labelText: '用户 ID（空=广播）'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            try {
              await context.read<AdminSession>().api.push(
                    title: _title.text.trim(),
                    body: _body.text.trim(),
                    userId: int.tryParse(_userId.text.trim()) ?? 0,
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已发送')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          child: const Text('发送站内信 / 推送'),
        ),
      ],
    );
  }
}

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});
  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  final _min = TextEditingController();
  final _latest = TextEditingController();
  final _apk = TextEditingController();
  final _ios = TextEditingController();
  final _notes = TextEditingController();
  String _force = '0';
  String _status = 'ACTIVE';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AdminSession>().api.dashboard();
      final s = (d['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      _min.text = '${s['min_version'] ?? ''}';
      _latest.text = '${s['latest_version'] ?? ''}';
      _apk.text = '${s['apk_download_url'] ?? ''}';
      _ios.text = '${s['ios_download_url'] ?? ''}';
      _notes.text = '${s['update_release_notes'] ?? ''}';
      _force = '${s['force_update'] ?? '0'}';
      _status = '${s['app_status'] ?? 'ACTIVE'}';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(String key, String value) async {
    try {
      await context.read<AdminSession>().api.setSetting(key, value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存 $key')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: '应用状态'),
          items: const [
            DropdownMenuItem(value: 'ACTIVE', child: Text('运行')),
            DropdownMenuItem(value: 'MAINTENANCE', child: Text('维护')),
            DropdownMenuItem(value: 'DISABLED', child: Text('停用')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _status = v);
            _save('app_status', v);
          },
        ),
        TextField(controller: _min, decoration: const InputDecoration(labelText: '最低版本')),
        TextField(controller: _latest, decoration: const InputDecoration(labelText: '最新版本')),
        DropdownButtonFormField<String>(
          initialValue: _force,
          decoration: const InputDecoration(labelText: '强制升级（仅低于最新版时拦截）'),
          items: const [
            DropdownMenuItem(value: '0', child: Text('否')),
            DropdownMenuItem(value: '1', child: Text('是')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _force = v);
            _save('force_update', v);
          },
        ),
        TextField(controller: _apk, decoration: const InputDecoration(labelText: 'APK 下载地址')),
        TextField(controller: _ios, decoration: const InputDecoration(labelText: 'iOS 下载地址')),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: '更新说明'), maxLines: 3),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            await _save('min_version', _min.text.trim());
            await _save('latest_version', _latest.text.trim());
            await _save('apk_download_url', _apk.text.trim());
            await _save('ios_download_url', _ios.text.trim());
            await _save('update_release_notes', _notes.text.trim());
          },
          child: const Text('保存版本与下载配置'),
        ),
      ],
    );
  }
}

class OperatorsPage extends StatefulWidget {
  const OperatorsPage({super.key});
  @override
  State<OperatorsPage> createState() => _OperatorsPageState();
}

class _OperatorsPageState extends State<OperatorsPage> {
  List<Map<String, dynamic>> _list = [];
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<AdminSession>().api.operators();
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AdminSession>().api;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: TextField(controller: _user, decoration: const InputDecoration(labelText: '新运营用户名'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: '初始密码'))),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                try {
                  await api.createOperator(_user.text.trim(), _pass.text);
                  _user.clear();
                  _pass.clear();
                  _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._list.map((a) => ListTile(
              title: Text('${a['username']}'),
              subtitle: Text('${a['role']} · ${a['is_enabled'] == true ? '启用' : '禁用'}'),
            )),
      ],
    );
  }
}
