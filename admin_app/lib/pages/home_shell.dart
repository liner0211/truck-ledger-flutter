import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../admin_session.dart';
import '../admin_updater.dart';
import '../ui/admin_widgets.dart';
import 'control_page.dart';
import 'dashboard_page.dart';
import 'messages_page.dart';
import 'operators_page.dart';
import 'users_page.dart';

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

  static const _wideBreakpoint = 700.0;

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
      final raw = await api.checkAdminAppUpdate(ver);
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
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final pages = <Widget>[
      const DashboardPage(),
      const UsersPage(),
      const MessagesPage(),
      if (admin.can('control.write')) const ControlPage(),
      if (admin.can('admins.manage')) const OperatorsPage(),
    ];

    final railDestinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('总览'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people),
        label: Text('用户'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.mail_outline),
        selectedIcon: Icon(Icons.mail),
        label: Text('消息'),
      ),
      if (admin.can('control.write'))
        const NavigationRailDestination(
          icon: Icon(Icons.tune_outlined),
          selectedIcon: Icon(Icons.tune),
          label: Text('控制面'),
        ),
      if (admin.can('admins.manage'))
        const NavigationRailDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: Text('会计账号'),
        ),
    ];

    final navDestinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: '总览'),
      const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: '用户'),
      const NavigationDestination(icon: Icon(Icons.mail_outline), selectedIcon: Icon(Icons.mail), label: '消息'),
      if (admin.can('control.write'))
        const NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: '控制面'),
      if (admin.can('admins.manage'))
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: '会计',
        ),
    ];

    if (_index >= pages.length) _index = 0;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('管理端'),
            const SizedBox(width: 10),
            Chip(
              label: Text(admin.username),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 6),
            Chip(
              label: Text(admin.roleLabel),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              backgroundColor: cs.secondaryContainer,
            ),
          ],
        ),
        actions: [
          const ThemeModeMenuButton(),
          IconButton(
            tooltip: '检查更新',
            onPressed: _checkingUpdate ? null : _checkUpdate,
            icon: _checkingUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
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
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.system_update, color: cs.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _updateBanner!,
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                    ),
                    FilledButton(onPressed: _installUpdate, child: const Text('立即更新')),
                  ],
                ),
              ),
            ),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: (i) => setState(() => _index = i),
                        labelType: NavigationRailLabelType.all,
                        destinations: railDestinations,
                      ),
                      VerticalDivider(width: 1, color: cs.outlineVariant),
                      Expanded(child: pages[_index]),
                    ],
                  )
                : pages[_index],
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: navDestinations,
            ),
    );
  }
}
