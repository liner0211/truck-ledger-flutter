import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:truck_ledger_flutter/services/api_http_client.dart';
import 'package:truck_ledger_flutter/services/auth_api.dart';
import 'package:truck_ledger_flutter/services/dns_over_https.dart';
import 'package:http/io_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device network probe', (tester) async {
    const host = 'truck.liner0211.online';
    const base = 'https://$host';

    // 1) 系统 DNS
    try {
      final sys = await InternetAddress.lookup(host);
      // ignore: avoid_print
      print('[PROBE] system DNS ok: ${sys.map((e) => e.address).join(', ')}');
    } catch (e) {
      // ignore: avoid_print
      print('[PROBE] system DNS fail: $e');
    }

    // 2) DoH
    try {
      final doh = await DnsOverHttps.resolve(host);
      // ignore: avoid_print
      print('[PROBE] DoH ok: ${doh.map((e) => e.address).join(', ')}');
    } catch (e) {
      // ignore: avoid_print
      print('[PROBE] DoH fail: $e');
    }

    // 3) 标准 IOClient（与 App 相同，不经 connectionFactory）
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

    // 4) apiHttpClient（App 实际路径）
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
