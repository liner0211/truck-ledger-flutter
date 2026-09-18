import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../services/profit_calculator.dart';

/// 圈次费用构成 / 利润率 / 支付来源可视化。
class TripStatCharts extends StatelessWidget {
  const TripStatCharts({
    super.key,
    required this.summary,
    required this.money,
  });

  final ProfitSummary summary;
  final String Function(double v) money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final expenseSlices = <_Slice>[
      _Slice('油费', summary.fuelExpense, cs.primary),
      _Slice('高速', summary.tollExpense, cs.tertiary),
      _Slice('其他', summary.otherExpense, cs.secondary),
      _Slice('信息费', summary.totalInfoFee, cs.outline),
      if (summary.etcTollReconcileFee > 0.000001)
        _Slice('ETC手续费', summary.etcTollReconcileFee, cs.error),
    ].where((s) => s.value > 0.000001).toList();

    final freight = summary.totalFreight;
    final profitPct = freight > 0.000001 ? summary.netProfit / freight * 100 : 0.0;
    final expensePct =
        freight > 0.000001 ? summary.totalExpense / freight * 100 : 0.0;

    final payTotal = summary.expenseByCash + summary.expenseByCompany;
    final cashPct =
        payTotal > 0.000001 ? summary.expenseByCash / payTotal * 100 : 0.0;
    final companyPct =
        payTotal > 0.000001 ? summary.expenseByCompany / payTotal * 100 : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('统计', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (expenseSlices.isNotEmpty) ...[
              Text('费用构成', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(
                height: 160,
                child: Row(
                  children: [
                    Expanded(
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 28,
                          sections: [
                            for (final s in expenseSlices)
                              PieChartSectionData(
                                value: s.value,
                                color: s.color,
                                title: '${_pct(s.value, summary.totalExpense)}%',
                                radius: 42,
                                titleStyle: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onPrimary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final s in expenseSlices)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: s.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${s.label} ${_pct(s.value, summary.totalExpense)}% · ${money(s.value)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text('相对运费', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            _PctBar(
              label: '利润率',
              percent: profitPct,
              color: profitPct >= 0 ? cs.primary : cs.error,
              trailing: money(summary.netProfit),
            ),
            const SizedBox(height: 6),
            _PctBar(
              label: '费用占比',
              percent: expensePct.clamp(0, 100),
              color: cs.tertiary,
              trailing: money(summary.totalExpense),
            ),
            if (payTotal > 0.000001) ...[
              const SizedBox(height: 12),
              Text('支付来源', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              _PctBar(
                label: '现金',
                percent: cashPct,
                color: cs.secondary,
                trailing: money(summary.expenseByCash),
              ),
              const SizedBox(height: 6),
              _PctBar(
                label: '公司/ETC侧',
                percent: companyPct,
                color: cs.primaryContainer,
                trailing: money(summary.expenseByCompany),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _pct(double part, double total) {
    if (total <= 0.000001) return '0';
    return (part / total * 100).toStringAsFixed(0);
  }
}

/// 首页工资汇总分段条。
class WageShareBar extends StatelessWidget {
  const WageShareBar({
    super.key,
    required this.totalDue,
    required this.paid,
    required this.unpaidReconciled,
    required this.money,
  });

  final double totalDue;
  final double paid;
  final double unpaidReconciled;
  final String Function(double v) money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (totalDue <= 0.000001) {
      return const SizedBox.shrink();
    }
    final other = (totalDue - paid - unpaidReconciled).clamp(0.0, totalDue);
    final paidPct = paid / totalDue * 100;
    final unpaidPct = unpaidReconciled / totalDue * 100;
    final otherPct = other / totalDue * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                if (paid > 0.000001)
                  Expanded(
                    flex: (paidPct * 10).round().clamp(1, 1000),
                    child: ColoredBox(color: cs.primary),
                  ),
                if (unpaidReconciled > 0.000001)
                  Expanded(
                    flex: (unpaidPct * 10).round().clamp(1, 1000),
                    child: ColoredBox(color: cs.tertiary),
                  ),
                if (other > 0.000001)
                  Expanded(
                    flex: (otherPct * 10).round().clamp(1, 1000),
                    child: ColoredBox(color: cs.outlineVariant),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '已发 ${paidPct.toStringAsFixed(0)}%（${money(paid)}）· '
          '未发 ${unpaidPct.toStringAsFixed(0)}%（${money(unpaidReconciled)}）· '
          '其余 ${otherPct.toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Slice {
  const _Slice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

class _PctBar extends StatelessWidget {
  const _PctBar({
    required this.label,
    required this.percent,
    required this.color,
    required this.trailing,
  });

  final String label;
  final double percent;
  final Color color;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final p = percent.isFinite ? percent : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('$label ${p.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13))),
            Text(trailing, style: const TextStyle(fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (p / 100).clamp(0.0, 1.0),
            minHeight: 8,
            color: color,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
