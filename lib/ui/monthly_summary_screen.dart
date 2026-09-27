import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:truck_ledger_editor/truck_ledger_editor.dart' show WageShareBar;

import '../models/trip_models.dart';
import '../services/profit_calculator.dart';
import '../services/trip_date.dart';
import '../state/ledger_controller.dart';

class MonthlySummaryScreen extends StatefulWidget {
  const MonthlySummaryScreen({super.key});

  @override
  State<MonthlySummaryScreen> createState() => _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends State<MonthlySummaryScreen> {
  late String _monthKey;

  static String _keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _monthKey = _keyOf(DateTime.now());
  }

  List<String> _availableMonths(List<TripLedger> rounds) {
    final keys = rounds.map(TripDate.monthKey).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final nowKey = _keyOf(DateTime.now());
    final prev = _prevMonth(nowKey);
    for (final k in [nowKey, prev]) {
      if (!keys.contains(k)) keys.add(k);
    }
    keys.sort((a, b) => b.compareTo(a));
    return keys;
  }

  String _prevMonth(String key) {
    final p = key.split('-');
    var y = int.parse(p[0]);
    var m = int.parse(p[1]);
    m -= 1;
    if (m < 1) {
      m = 12;
      y -= 1;
    }
    return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LedgerController>();
    final rounds = ctrl.book.rounds;
    final months = _availableMonths(rounds);
    final nowKey = _keyOf(DateTime.now());
    final prevKey = _prevMonth(nowKey);
    final monthRounds =
        rounds.where((r) => TripDate.monthKey(r) == _monthKey).toList();
    final sums = monthRounds.map(ProfitCalculator.calculate).toList();

    var freight = 0.0;
    var fuel = 0.0;
    var fuelKg = 0.0;
    var toll = 0.0;
    var other = 0.0;
    var info = 0.0;
    var profit = 0.0;
    var wage = 0.0;
    var wagePaid = 0.0;
    var unpaidReconciled = 0.0;
    var reconciled = 0;
    for (var i = 0; i < monthRounds.length; i++) {
      final s = sums[i];
      final r = monthRounds[i];
      freight += s.totalFreight;
      fuel += s.fuelExpense;
      fuelKg += s.fuelKilogramsTotal;
      toll += s.tollExpense;
      other += s.otherExpense;
      info += s.totalInfoFee;
      profit += s.netProfit;
      wage += s.driverWagePayable;
      if (r.isSalarySettled) {
        wagePaid += s.driverWagePayable;
      } else if (r.isReconciled) {
        unpaidReconciled += s.driverWagePayable;
      }
      if (r.isReconciled) reconciled++;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('按月汇总')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => setState(() => _monthKey = nowKey),
                child: Text(_monthKey == nowKey ? '本月 ✓' : '本月'),
              ),
              FilledButton.tonal(
                onPressed: () => setState(() => _monthKey = prevKey),
                child: Text(_monthKey == prevKey ? '上月 ✓' : '上月'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: months.contains(_monthKey) ? _monthKey : months.first,
            decoration: const InputDecoration(
              labelText: '选择月份',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final k in months)
                DropdownMenuItem(value: k, child: Text(TripDate.monthLabel(k))),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _monthKey = v);
            },
          ),
          const SizedBox(height: 16),
          Text(
            TripDate.monthLabel(_monthKey),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '共 ${monthRounds.length} 圈 · 已交账 $reconciled 圈',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          if (monthRounds.isEmpty)
            const Card(
              child: ListTile(
                title: Text('本月暂无圈次'),
                subtitle: Text('新建圈次后会按开始时间归入对应月份'),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _row(context, '运费合计', ctrl.money(freight)),
                    _row(context, '油费', ctrl.money(fuel)),
                    if (fuelKg > 0.000001)
                      _row(
                        context,
                        '气耗',
                        '${fuelKg.toStringAsFixed(fuelKg == fuelKg.roundToDouble() ? 0 : 2)} kg',
                      ),
                    _row(context, '高速费', ctrl.money(toll)),
                    _row(context, '信息费', ctrl.money(info)),
                    _row(context, '其他费用', ctrl.money(other)),
                    const Divider(),
                    _row(context, '利润合计', ctrl.money(profit), emphasize: true),
                    _row(context, '司机应发工资', ctrl.money(wage), emphasize: true),
                    _row(context, '其中已发', ctrl.money(wagePaid)),
                    _row(context, '未发（应发−已发）', ctrl.money(wage - wagePaid)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            WageShareBar(
              totalDue: wage,
              paid: wagePaid,
              unpaidReconciled: unpaidReconciled,
              money: ctrl.money,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool emphasize = false}) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
