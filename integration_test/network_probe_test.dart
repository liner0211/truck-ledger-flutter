import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:truck_ledger_flutter/services/api_http_client.dart';
import 'package:truck_ledger_flutter/services/auth_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device network probe', (tester) async {
    const host = 'truck.liner0211.online';
    const base = 'https://$host';

    try {
      final sys = await InternetAddress.lookup(host);
      // ignore: avoid_print
      print('[PROBE] system DNS ok: ${sys.map((e) => e.address).join(', ')}');
    } catch (e) {
      // ignore: avoid_print
      print('[PROBE] system DNS fail: $e');
    }

    try {
      final client = IOClient(HttpClient());
      final r = await client
          .get(Uri.parse('$base/api/health'))
          .timeout(const Duration(seconds: 12));
      // ignore: avoid_print
      print('[PROBE] IOClient ${r.statusCode} ${r.body}');
      client.close();
    } catch (e) {
      // ignore: avoid_print
      print('[PROBE] IOClient fail: $e');
    }

    initApiHttpClient();
    try {
      await AuthApi(baseUrl: base).checkHealth();
      // ignore: avoid_print
      print('[PROBE] apiHttpClient health OK');
    } catch (e, st) {
      // ignore: avoid_print
      print('[PROBE] apiHttpClient health FAIL: $e\n$st');
      fail('apiHttpClient failed: $e');
    }
  });
}
