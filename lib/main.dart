import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/ledger_controller.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => LedgerController()..load(),
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
      home: const HomeScreen(),
    );
  }
}
