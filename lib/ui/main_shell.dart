import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../utils/system_nav_inset.dart';
import 'home_screen.dart';
import 'me_screen.dart';
import 'monthly_summary_screen.dart';

/// 登录后主壳：底部 圈次 | 汇总 | 我的。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    SystemNavInset.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _badgeIcon({
    required IconData icon,
    required IconData selectedIcon,
    required bool selected,
    required int count,
  }) {
    final child = Icon(selected ? selectedIcon : icon);
    if (count <= 0) return child;
    final label = count > 99 ? '99+' : '$count';
    return Badge(
      label: Text(label),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<AuthController>().unreadMessages;
    // 仅虚拟按键时按系统高度抬底；手势导航为 0，贴边全屏
    final bottomInset = SystemNavInset.bottomForNavBar(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          MonthlySummaryScreen(asTab: true),
          MeScreen(),
        ],
      ),
      bottomNavigationBar: Material(
        elevation: 3,
        color: Theme.of(context).navigationBarTheme.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.local_shipping_outlined),
                selectedIcon: Icon(Icons.local_shipping),
                label: '圈次',
              ),
              const NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: '汇总',
              ),
              NavigationDestination(
                icon: _badgeIcon(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  selected: false,
                  count: unread,
                ),
                selectedIcon: _badgeIcon(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  selected: true,
                  count: unread,
                ),
                label: unread > 0 ? '我的($unread)' : '我的',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
