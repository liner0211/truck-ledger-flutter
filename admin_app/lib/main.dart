import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api.dart';
import 'admin_updater.dart';
import 'theme_controller.dart';
import 'user_ledger_page.dart';
import 'user_ops_page.dart';

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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController(prefs)),
        ChangeNotifierProvider(create: (_) => AdminSession(prefs)..restore()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: '卡车记账管理端',
          theme: ThemeController.lightTheme(),
          darkTheme: ThemeController.darkTheme(),
          themeMode: theme.mode,
          home: const _Gate(),
        ),
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
      appBar: AppBar(
        actions: [
          PopupMenuButton<ThemeMode>(
            tooltip: '外观',
            icon: const Icon(Icons.brightness_6_outlined),
            initialValue: context.watch<ThemeController>().mode,
            onSelected: (mode) => context.read<ThemeController>().setMode(mode),
            itemBuilder: (context) => const [
              PopupMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
              PopupMenuItem(value: ThemeMode.light, child: Text('浅色')),
              PopupMenuItem(value: ThemeMode.dark, child: Text('深色')),
            ],
          ),
        ],
      ),
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
  String? _updateBanner;
  String? _updateUrl;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final info = await PackageInfo.fromPlatform();
      final ver = '${info.version}+${info.buildNumber}';
      final platform = kIsWeb
          ? 'web'
          : (Platform.isAndroid
              ? 'android'
              : Platform.isIOS
                  ? 'ios'
                  : Platform.isLinux
                      ? 'linux'
                      : Platform.isWindows
                          ? 'windows'
                          : 'unknown');
      final api = context.read<AdminSession>().api;
      // platform via header is not set on AdminApi; pass in body is enough for version
      final raw = await api.checkAdminAppUpdate(ver);
      // re-call with platform: patch by temporarily using http would be better;
      // for now version compare is enough; download_url may default to apk
      final update = (raw['update'] as Map?)?.cast<String, dynamic>();
      if (update == null) return;
      final available = update['available'] == true;
      final url = '${update['download_url'] ?? ''}';
      final latest = '${update['latest_version'] ?? ''}';
      if (available && url.isNotEmpty && mounted) {
        setState(() {
          _updateBanner = '管理端有新版本 $latest（当前 $ver）';
          _updateUrl = url;
        });
      }
      // Prefer platform-specific URL from settings if check returned apk for desktop
      if (available && mounted && (platform == 'linux' || platform == 'windows')) {
        try {
          final d = await api.dashboard();
          final s = (d['settings'] as Map?)?.cast<String, dynamic>() ?? {};
          final prefer = platform == 'linux'
              ? '${s['admin_linux_download_url'] ?? ''}'
              : '${s['admin_windows_download_url'] ?? ''}';
          if (prefer.isNotEmpty) {
            setState(() => _updateUrl = prefer);
          }
        } catch (_) {}
      }
    } catch (_) {
      // ignore soft check failures
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _installUpdate() async {
    final url = _updateUrl;
    if (url == null || url.isEmpty) return;
    try {
      await AdminAppUpdater.openOrInstall(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

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
        const NavigationRailDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: Text('会计账号')),
    ];
    if (_index >= pages.length) _index = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('管理端 · ${admin.username}（${admin.roleLabel}）'),
        actions: [
          PopupMenuButton<ThemeMode>(
            tooltip: '外观',
            icon: const Icon(Icons.brightness_6_outlined),
            initialValue: context.watch<ThemeController>().mode,
            onSelected: (mode) => context.read<ThemeController>().setMode(mode),
            itemBuilder: (context) => const [
              PopupMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
              PopupMenuItem(value: ThemeMode.light, child: Text('浅色')),
              PopupMenuItem(value: ThemeMode.dark, child: Text('深色')),
            ],
          ),
          IconButton(
            tooltip: '检查更新',
            onPressed: _checkingUpdate ? null : _checkUpdate,
            icon: const Icon(Icons.system_update_alt),
          ),
          IconButton(
            tooltip: '退出',
            onPressed: () => s.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_updateBanner != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                dense: true,
                title: Text(_updateBanner!),
                trailing: FilledButton(
                  onPressed: _installUpdate,
                  child: const Text('更新'),
                ),
                onTap: _installUpdate,
              ),
            ),
          Expanded(
            child: Row(
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
          ),
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
  List<Map<String, dynamic>> _audits = [];
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AdminSession>().api;
      final d = await api.dashboard();
      List<Map<String, dynamic>> audits = const [];
      try {
        audits = await api.audits(limit: 30);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _data = d;
          _audits = audits;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  String _fmtMs(dynamic ms) {
    final n = (ms is num) ? ms.toInt() : int.tryParse('$ms') ?? 0;
    if (n <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(n);
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
    final health = (_data!['health'] as Map?)?.cast<String, dynamic>() ?? {};
    final settings = (_data!['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final checks = (health['checks'] as Map?)?.cast<String, dynamic>() ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat('用户', '${stats['user_count'] ?? '—'}'),
            _stat('圈次', '${stats['round_count'] ?? '—'}'),
            _stat('设备', '${stats['device_count'] ?? '—'}'),
            _stat('站内信', '${stats['message_count'] ?? '—'}'),
            if (stats['attachment_count'] != null) _stat('附件', '${stats['attachment_count']}'),
            if (stats['data_size_mb'] != null) _stat('数据MB', '${stats['data_size_mb']}'),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: Text('系统健康：${health['status'] ?? '—'}'),
            subtitle: Text(
              checks.isEmpty
                  ? '—'
                  : checks.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            ),
            isThreeLine: checks.length > 1,
          ),
        ),
        if (context.watch<AdminSession>().admin?.can('control.write') == true)
          Card(
            child: ListTile(
              title: const Text('应用控制面快照'),
              subtitle: Text(
                '状态 ${settings['app_status']} · 注册 ${settings['registration_enabled'] == '1' || settings['registration_enabled'] == true ? '开' : '关'} · '
                '最低 ${settings['min_version']} · 最新 ${settings['latest_version']} · 强更 ${settings['force_update']}',
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('最近审计', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_audits.isEmpty)
          const Card(child: ListTile(title: Text('暂无审计记录')))
        else
          ..._audits.take(20).map((a) {
            return Card(
              child: ListTile(
                dense: true,
                title: Text('${a['action'] ?? ''} · ${a['target_type'] ?? ''} ${a['target_id'] ?? ''}'),
                subtitle: Text(_fmtMs(a['created_at'])),
              ),
            );
          }),
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final list = await context.read<AdminSession>().api.users();
      if (mounted) {
        setState(() {
          _users = list;
          _err = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '$e';
          _loading = false;
        });
      }
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
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 200, child: LinearProgressIndicator()),
            SizedBox(height: 12),
            Text('加载用户列表…'),
          ],
        ),
      );
    }
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
              onTap: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => UserLedgerPage(user: u),
                  ),
                );
              },
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'ledger') {
                    if (!mounted) return;
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => UserLedgerPage(user: u),
                      ),
                    );
                    return;
                  }
                  if (v == 'ops') {
                    if (!mounted) return;
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => UserOpsPage(user: u),
                      ),
                    );
                    return;
                  }
                  if (v == 'extend') {
                    await _act(id, 'extend', body: {'days': 14});
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
                  const PopupMenuItem(value: 'ledger', child: Text('查看/编辑账本')),
                  const PopupMenuItem(value: 'ops', child: Text('快照与设备')),
                  const PopupMenuItem(value: 'extend', child: Text('延期试用 14 天')),
                  const PopupMenuItem(value: 'convert', child: Text('转正式')),
                  const PopupMenuItem(value: 'kick', child: Text('踢下线')),
                  const PopupMenuItem(value: 'enable', child: Text('启用')),
                  const PopupMenuItem(value: 'disable', child: Text('禁用')),
                  const PopupMenuItem(value: 'reset', child: Text('重置密码')),
                  if (canDelete) const PopupMenuItem(value: 'delete', child: Text('删除用户（开发者）')),
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
  final _maintenance = TextEditingController();
  final _announcement = TextEditingController();
  final _offlineGrace = TextEditingController();
  final _trialDays = TextEditingController();
  final _trialRounds = TextEditingController();
  final _trialAttach = TextEditingController();
  final _adminMin = TextEditingController();
  final _adminLatest = TextEditingController();
  final _adminApk = TextEditingController();
  final _adminIos = TextEditingController();
  final _adminLinux = TextEditingController();
  final _adminWin = TextEditingController();
  final _adminNotes = TextEditingController();
  String _force = '0';
  String _adminForce = '0';
  String _status = 'ACTIVE';
  String _expiry = 'readonly';
  bool _registration = true;
  bool _ffExcel = true;
  bool _ffBackup = true;
  bool _ffMessages = true;
  bool _ffWeb = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _min.dispose();
    _latest.dispose();
    _apk.dispose();
    _ios.dispose();
    _notes.dispose();
    _maintenance.dispose();
    _announcement.dispose();
    _offlineGrace.dispose();
    _trialDays.dispose();
    _trialRounds.dispose();
    _trialAttach.dispose();
    _adminMin.dispose();
    _adminLatest.dispose();
    _adminApk.dispose();
    _adminIos.dispose();
    _adminLinux.dispose();
    _adminWin.dispose();
    _adminNotes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<AdminSession>().api.allSettings();
      _min.text = '${s['min_version'] ?? ''}';
      _latest.text = '${s['latest_version'] ?? ''}';
      _apk.text = '${s['apk_download_url'] ?? ''}';
      _ios.text = '${s['ios_download_url'] ?? ''}';
      _notes.text = '${s['update_release_notes'] ?? ''}';
      _force = '${s['force_update'] ?? '0'}';
      _status = '${s['app_status'] ?? 'ACTIVE'}';
      _maintenance.text = '${s['maintenance_message'] ?? ''}';
      _announcement.text = '${s['announcement'] ?? ''}';
      _offlineGrace.text = '${s['offline_grace_sec'] ?? ''}';
      _trialDays.text = '${s['trial_days'] ?? ''}';
      _trialRounds.text = '${s['trial_max_rounds'] ?? ''}';
      _trialAttach.text = '${s['trial_max_attachments'] ?? ''}';
      _expiry = '${s['expiry_policy'] ?? 'readonly'}';
      _registration = '${s['registration_enabled'] ?? '1'}' == '1';
      _adminMin.text = '${s['admin_min_version'] ?? ''}';
      _adminLatest.text = '${s['admin_latest_version'] ?? ''}';
      _adminApk.text = '${s['admin_apk_download_url'] ?? ''}';
      _adminIos.text = '${s['admin_ios_download_url'] ?? ''}';
      _adminLinux.text = '${s['admin_linux_download_url'] ?? ''}';
      _adminWin.text = '${s['admin_windows_download_url'] ?? ''}';
      _adminNotes.text = '${s['admin_update_release_notes'] ?? ''}';
      _adminForce = '${s['admin_force_update'] ?? '0'}';
      try {
        final ff = jsonDecode('${s['feature_flags'] ?? '{}'}');
        if (ff is Map) {
          _ffExcel = ff['excel_export'] != false;
          _ffBackup = ff['backup_import'] != false;
          _ffMessages = ff['messages'] != false;
          _ffWeb = ff['web_ledger'] != false;
        }
      } catch (_) {}
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

  Future<void> _saveFeatureFlags() async {
    final raw = jsonEncode({
      'excel_export': _ffExcel,
      'backup_import': _ffBackup,
      'messages': _ffMessages,
      'web_ledger': _ffWeb,
    });
    await _save('feature_flags', raw);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('开放用户注册'),
          value: _registration,
          onChanged: (v) async {
            setState(() => _registration = v);
            await _save('registration_enabled', v ? '1' : '0');
          },
        ),
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
        TextField(controller: _maintenance, decoration: const InputDecoration(labelText: '维护文案')),
        TextField(controller: _announcement, decoration: const InputDecoration(labelText: '全局公告'), maxLines: 2),
        TextField(controller: _offlineGrace, decoration: const InputDecoration(labelText: '离线宽限秒数')),
        TextField(controller: _trialDays, decoration: const InputDecoration(labelText: '试用天数')),
        TextField(controller: _trialRounds, decoration: const InputDecoration(labelText: '试用圈次上限(0不限)')),
        TextField(controller: _trialAttach, decoration: const InputDecoration(labelText: '试用附件上限(0不限)')),
        DropdownButtonFormField<String>(
          initialValue: _expiry,
          decoration: const InputDecoration(labelText: '到期策略'),
          items: const [
            DropdownMenuItem(value: 'readonly', child: Text('只读')),
            DropdownMenuItem(value: 'block', child: Text('禁止登录')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _expiry = v);
            _save('expiry_policy', v);
          },
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () async {
            await _save('maintenance_message', _maintenance.text.trim());
            await _save('announcement', _announcement.text.trim());
            await _save('offline_grace_sec', _offlineGrace.text.trim());
            await _save('trial_days', _trialDays.text.trim());
            await _save('trial_max_rounds', _trialRounds.text.trim());
            await _save('trial_max_attachments', _trialAttach.text.trim());
          },
          child: const Text('保存公告 / 试用 / 离线宽限'),
        ),
        const Divider(height: 32),
        Text('功能开关', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          title: const Text('Excel / 报表导出'),
          value: _ffExcel,
          onChanged: (v) => setState(() => _ffExcel = v),
        ),
        SwitchListTile(
          title: const Text('备份导入导出'),
          value: _ffBackup,
          onChanged: (v) => setState(() => _ffBackup = v),
        ),
        SwitchListTile(
          title: const Text('消息中心'),
          value: _ffMessages,
          onChanged: (v) => setState(() => _ffMessages = v),
        ),
        SwitchListTile(
          title: const Text('Web 账本入口提示'),
          value: _ffWeb,
          onChanged: (v) => setState(() => _ffWeb = v),
        ),
        FilledButton.tonal(onPressed: _saveFeatureFlags, child: const Text('保存功能开关')),
        const Divider(height: 32),
        Text('司机端版本与下载', style: Theme.of(context).textTheme.titleMedium),
        TextField(controller: _min, decoration: const InputDecoration(labelText: '最低版本')),
        TextField(controller: _latest, decoration: const InputDecoration(labelText: '最新版本（如 1.2.0+45）')),
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
        TextField(controller: _apk, decoration: const InputDecoration(labelText: '司机端 APK 下载地址')),
        TextField(controller: _ios, decoration: const InputDecoration(labelText: '司机端 iOS IPA 下载地址')),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: '司机端更新说明'), maxLines: 3),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            await _save('min_version', _min.text.trim());
            await _save('latest_version', _latest.text.trim());
            await _save('apk_download_url', _apk.text.trim());
            await _save('ios_download_url', _ios.text.trim());
            await _save('update_release_notes', _notes.text.trim());
          },
          child: const Text('保存司机端版本与下载配置'),
        ),
        const Divider(height: 32),
        Text('管理端更新', style: Theme.of(context).textTheme.titleMedium),
        TextField(controller: _adminMin, decoration: const InputDecoration(labelText: '管理端最低版本')),
        TextField(controller: _adminLatest, decoration: const InputDecoration(labelText: '管理端最新版本')),
        DropdownButtonFormField<String>(
          initialValue: _adminForce,
          decoration: const InputDecoration(labelText: '管理端强制升级'),
          items: const [
            DropdownMenuItem(value: '0', child: Text('否')),
            DropdownMenuItem(value: '1', child: Text('是')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _adminForce = v);
            _save('admin_force_update', v);
          },
        ),
        TextField(controller: _adminApk, decoration: const InputDecoration(labelText: '管理端 APK')),
        TextField(controller: _adminIos, decoration: const InputDecoration(labelText: '管理端 IPA')),
        TextField(controller: _adminLinux, decoration: const InputDecoration(labelText: '管理端 Linux')),
        TextField(controller: _adminWin, decoration: const InputDecoration(labelText: '管理端 Windows')),
        TextField(controller: _adminNotes, decoration: const InputDecoration(labelText: '管理端更新说明'), maxLines: 2),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () async {
            await _save('admin_min_version', _adminMin.text.trim());
            await _save('admin_latest_version', _adminLatest.text.trim());
            await _save('admin_apk_download_url', _adminApk.text.trim());
            await _save('admin_ios_download_url', _adminIos.text.trim());
            await _save('admin_linux_download_url', _adminLinux.text.trim());
            await _save('admin_windows_download_url', _adminWin.text.trim());
            await _save('admin_update_release_notes', _adminNotes.text.trim());
          },
          child: const Text('保存管理端更新配置'),
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
        Text(
          '会计管理员可管理用户与账本；控制面/删用户/设备吊销等仅开发者可见。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextField(controller: _user, decoration: const InputDecoration(labelText: '新会计管理员用户名'))),
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
        ..._list.map((a) {
          final id = (a['id'] as num).toInt();
          final role = '${a['role']}';
          final enabled = a['is_enabled'] == true;
          final label = a['role_label'] ?? (role == 'super' ? '开发者' : '会计管理员');
          return Card(
            child: ListTile(
              title: Text('${a['username']}'),
              subtitle: Text('$label · ${enabled ? '启用' : '禁用'}'),
              trailing: role == 'super'
                  ? const Text('不可删', style: TextStyle(color: Colors.grey))
                  : PopupMenuButton<String>(
                      onSelected: (v) async {
                        try {
                          if (v == 'enable') {
                            await api.setOperatorEnabled(id, true);
                          } else if (v == 'disable') {
                            await api.setOperatorEnabled(id, false);
                          } else if (v == 'reset') {
                            final ctrl = TextEditingController();
                            final pass = await showDialog<String>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('重置密码'),
                                content: TextField(
                                  controller: ctrl,
                                  obscureText: true,
                                  decoration: const InputDecoration(labelText: '新密码'),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                                  FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('确定')),
                                ],
                              ),
                            );
                            if (pass == null || pass.length < 6) return;
                            await api.resetOperatorPassword(id, pass);
                          } else if (v == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('删除会计管理员'),
                                content: Text('确定删除 ${a['username']}？'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              final msg = await api.deleteOperator(id);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                              }
                            }
                          }
                          _load();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        if (!enabled) const PopupMenuItem(value: 'enable', child: Text('启用')),
                        if (enabled) const PopupMenuItem(value: 'disable', child: Text('禁用')),
                        const PopupMenuItem(value: 'reset', child: Text('重置密码')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
            ),
          );
        }),
      ],
    );
  }
}
