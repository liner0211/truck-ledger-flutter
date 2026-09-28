import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_nav.dart';
import 'services/api_http_client.dart';
import 'services/push_bootstrap.dart';
import 'state/auth_controller.dart';
import 'state/ledger_controller.dart';
import 'state/theme_controller.dart';
import 'ui/auth_gate.dart';
import 'ui/permission_bootstrap_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initApiHttpClient();
  await PushBootstrap.ensureInitialized();
  final theme = ThemeController();
  await theme.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider(create: (_) => AuthController()..load()),
        ChangeNotifierProxyProvider<AuthController, LedgerController>(
          create: (_) => LedgerController(),
          update: (_, auth, ledger) {
            final c = ledger ?? LedgerController();
            c.attachAuth(auth);
            if (!c.isLoaded) {
              c.load();
            }
            return c;
          },
        ),
      ],
      child: const TruckLedgerApp(),
    ),
  );
}

class TruckLedgerApp extends StatelessWidget {
  const TruckLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp(
      title: '卡车记账',
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
      home: const PermissionBootstrapGate(child: AuthGate()),
    );
  }
}
