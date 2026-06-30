import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_http_client.dart';
import 'state/auth_controller.dart';
import 'state/ledger_controller.dart';
import 'ui/auth_gate.dart';
import 'ui/permission_bootstrap_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initApiHttpClient();
  runApp(
    MultiProvider(
      providers: [
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
    return MaterialApp(
      title: '卡车记账',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20)),
        useMaterial3: true,
      ),
      home: const PermissionBootstrapGate(child: AuthGate()),
    );
  }
}
