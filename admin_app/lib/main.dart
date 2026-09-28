import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_session.dart';
import 'app_nav.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'services/local_push_service.dart';
import 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalPushService.instance.init().timeout(const Duration(seconds: 5));
  } catch (_) {}
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
          navigatorKey: AppNav.navigatorKey,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeController.lightTheme(),
          darkTheme: ThemeController.darkTheme(),
          themeMode: theme.mode,
          home: const _Gate(),
        ),
      ),
    );
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
