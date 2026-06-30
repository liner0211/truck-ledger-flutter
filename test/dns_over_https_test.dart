import 'package:flutter_test/flutter_test.dart';
import 'package:truck_ledger_flutter/services/dns_over_https.dart';

void main() {
  test('DoH resolves truck.liner0211.online', () async {
    final addrs = await DnsOverHttps.resolve('truck.liner0211.online');
    expect(addrs, isNotEmpty);
    expect(addrs.first.address, isNotEmpty);
  });
}
