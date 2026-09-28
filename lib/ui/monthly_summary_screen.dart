import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip_models.dart';
import '../services/profit_calculator.dart';
import '../services/trip_date.dart';
import '../state/ledger_controller.dart';
import 'trip_detail_screen.dart';

/// 汇总：全部圈次 / 按月；[asTab] 为 true 时作为底部「汇总」Tab。
class MonthlySummaryScreen extends StatefulWidget {
  const MonthlySummaryScreen({super.key, this.asTab = false});

  final bool asTab;

  @override
  State<MonthlySummaryScreen> createState() => _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends State<MonthlySummaryScreen> {
  static const _allKey = '__all__';

  /// `_allKey` = 全部圈次；否则为 `yyyy-MM`。
  late String _periodKey;

  static String _keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    // 默认看全部，方便一眼看工资总账；仍可切到按月。
    _periodKey = _allKey;
  }

  bool get _isAll => _periodKey == _allKey;

  List<String> _availableMonths(List<TripLedger> rounds) {
    final keys = rounds.map(TripDate.monthKey).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final nowKey = _keyOf(DateTime.now());
    final prev = _shiftMonth(nowKey, -1);
    for (final k in [nowKey, prev]) {
      if (!keys.contains(k)) keys.add(k);
    }
    keys.sort((a, b) => b.compareTo(a));
    return keys;
  }

  String _shiftMonth(String key, int delta) {
    final p = key.split('-');
    var y = int.parse(p[0]);
    var m = int.parse(p[1]) + delta;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LedgerController>();
    final rounds = ctrl.book.rounds;
    final months = _availableMonths(rounds);

    String periodKey = _periodKey;
    if (!_isAll && !months.contains(periodKey) && months.isNotEmpty) {
      periodKey = months.first;
    }

    final scopedRounds = _isAll
        ? List<TripLedger>.from(rounds)
        : rounds.where((r) => TripDate.monthKey(r) == periodKey).toList();
    final sums = scopedRounds.map(ProfitCalculator.calculate).toList();

    var profit = 0.0;
    var wage = 0.0;
    var wagePaid = 0.0;
    var unpaidReconciled = 0.0;
    var freight = 0.0;
    var fuel = 0.0;
    var toll = 0.0;
    var other = 0.0;
    var info = 0.0;
    var reconciled = 0;
    for (var i = 0; i < scopedRounds.length; i++) {
      final s = sums[i];
      final r = scopedRounds[i];
      profit += s.netProfit;
      wage += s.driverWagePayable;
      freight += s.totalFreight;
      fuel += s.fuelExpense;
      toll += s.tollExpense;
      other += s.otherExpense;
      info += s.totalInfoFee;
      if (r.isSalarySettled) {
        wagePaid += s.driverWagePayable;
      } else if (r.isReconciled) {
        unpaidReconciled += s.driverWagePayable;
      }
      if (r.isReconciled) reconciled++;
    }
    final unpaidAll = wage - wagePaid;
    final cs = Theme.of(context).colorScheme;
    final amber = const Color(0xFFE8A317);
    final wageProgress = wage > 0.000001 ? (wagePaid / wage).clamp(0.0, 1.0) : 0.0;
    final profitLabel = _isAll ? '全部净利' : '本月净利';
    final wageLabel = _isAll ? '全部工资' : '本月工资';
    final emptyTitle = _isAll ? '暂无圈次' : '本月暂无圈次';
    final emptySub = _isAll
        ? '在「圈次」里记一圈后即可在此汇总'
        : '新建圈次后会按开始时间归入对应月份';

    return Scaffold(
      appBar: AppBar(
        title: const Text('汇总'),
        centerTitle: widget.asTab,
        automaticallyImplyLeading: !widget.asTab,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('全部'), icon: Icon(Icons.select_all, size: 18)),
              ButtonSegment(value: false, label: Text('按月'), icon: Icon(Icons.calendar_month_outlined, size: 18)),
            ],
            selected: {_isAll},
            onSelectionChanged: (set) {
              final all = set.first;
              setState(() {
                if (all) {
                  _periodKey = _allKey;
                } else {
                  _periodKey = months.contains(_keyOf(DateTime.now()))
                      ? _keyOf(DateTime.now())
                      : (months.isNotEmpty ? months.first : _keyOf(DateTime.now()));
                }
              });
            },
          ),
          if (!_isAll) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: '上一月',
                  onPressed: () =>
                      setState(() => _periodKey = _shiftMonth(periodKey, -1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    TripDate.monthLabel(periodKey),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: '下一月',
                  onPressed: () =>
                      setState(() => _periodKey = _shiftMonth(periodKey, 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (months.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: DropdownButtonFormField<String>(
                  initialValue: periodKey,
                  decoration: const InputDecoration(
                    labelText: '选择月份',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final k in months)
                      DropdownMenuItem(
                        value: k,
                        child: Text(TripDate.monthLabel(k)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _periodKey = v);
                  },
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '统计账本内全部圈次',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profitLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ctrl.money(profit),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '共 ${scopedRounds.length} 个圈次 · 已交账 $reconciled 圈',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    wageLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MoneyCol(
                          label: '应付',
                          value: ctrl.money(wage),
                        ),
                      ),
                      Expanded(
                        child: _MoneyCol(
                          label: '已发',
                          value: ctrl.money(wagePaid),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: wageProgress,
                      minHeight: 8,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    unpaidReconciled > 0.000001
                        ? '未发 ${ctrl.money(unpaidAll)}（其中已交账未发 ${ctrl.money(unpaidReconciled)}）'
                        : '未发 ${ctrl.money(unpaidAll)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: unpaidAll > 0.000001 ? amber : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
          if (scopedRounds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row(context, '运费合计', ctrl.money(freight)),
                    _row(context, '油费', ctrl.money(fuel)),
                    _row(context, '高速费', ctrl.money(toll)),
                    _row(context, '信息费', ctrl.money(info)),
                    _row(context, '其他费用', ctrl.money(other)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '圈次明细',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < scopedRounds.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    scopedRounds[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${TripDate.monthLabel(TripDate.monthKey(scopedRounds[i]))} · '
                    '${scopedRounds[i].isReconciled ? '已交账' : '未交账'} · '
                    '${scopedRounds[i].isSalarySettled ? '工资已发' : '工资未发'}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        ctrl.money(sums[i].netProfit),
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        ctrl.money(sums[i].driverWagePayable),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  onTap: () {
                    final round = scopedRounds[i];
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => TripDetailScreen(
                          initial: round.copy(),
                          money: ctrl.money,
                          allRounds: ctrl.book.rounds,
                          onReplace: (updated) => ctrl.replaceTrip(updated),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ] else
            Card(
              child: ListTile(
                title: Text(emptyTitle),
                subtitle: Text(emptySub),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value),
        ],
      ),
    );
  }
}

class _MoneyCol extends StatelessWidget {
  const _MoneyCol({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
