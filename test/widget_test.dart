import 'package:flutter_test/flutter_test.dart';

import 'package:truck_ledger_flutter/main.dart';

void main() {
  testWidgets('首页可见标题', (WidgetTester tester) async {
    await tester.pumpWidget(const TruckLedgerApp());
    expect(find.text('卡车记账'), findsWidgets);
    expect(find.textContaining('Flutter'), findsOneWidget);
  });
}
