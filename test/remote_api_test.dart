import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:truck_ledger_flutter/models/trip_models.dart';
import 'package:truck_ledger_flutter/services/api_http_client.dart';
import 'package:truck_ledger_flutter/services/auth_api.dart';
import 'package:truck_ledger_flutter/services/sync_service.dart';

/// 与 App 相同代码路径的远程 API 联调（本机运行，非 Android）。
///
///   flutter test test/remote_api_test.dart
///
/// 可选环境变量：
///   API_BASE_URL  默认 https://truck.liner0211.online
const _baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://truck.liner0211.online',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthApi auth;
  late String username;
  const password = 'TestPass123456';

  setUpAll(() {
    HttpOverrides.global = null;
    initApiHttpClient();
  });

  setUp(() {
    auth = AuthApi(baseUrl: _baseUrl);
    username = 'flutter_test_${DateTime.now().millisecondsSinceEpoch}';
  });

  test('health → register → push ledger → pull ledger', () async {
    await auth.checkHealth();

    final reg = await auth.register(
      username: username,
      password: password,
      licensePlate: '京A12345',
    );
    expect(reg.token, isNotEmpty);
    expect(reg.username, username);

    final sync = SyncService(baseUrl: _baseUrl, token: reg.token);

    final book = LedgerBook(
      rounds: [
        TripLedger(
          id: 'flutter-test-trip',
          title: 'Flutter本地测试圈次',
          startPlace: '2026-01-01 08:00',
          endPlace: '2026-01-02 18:00',
          createdAt: DateTime(2026, 1, 1, 8),
          isReconciled: false,
          isSalarySettled: false,
          routeLegs: [],
          expenses: [],
          cashAdvances: [],
        ),
      ],
    );

    final updatedAt = await sync.push(book);
    expect(updatedAt, greaterThan(0));

    final remote = await sync.pull();
    expect(remote.book.rounds.length, 1);
    expect(remote.book.rounds.first.title, 'Flutter本地测试圈次');
    expect(remote.updatedAt, updatedAt);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
