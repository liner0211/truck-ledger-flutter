import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/trip_models.dart';
import '../services/profit_calculator.dart';
import '../services/trip_excel_exporter.dart';
import 'advance_editor_page.dart';
import 'expense_editor_page.dart';
import 'route_editor_page.dart';
import 'trip_meta_editor.dart';
import 'widgets/attachment_thumb_strip.dart';
import 'widgets/ledger_stat_charts.dart';

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    super.key,
    required this.initial,
    required this.onReplace,
    required this.money,
    this.allRounds = const [],
  });

  final TripLedger initial;
  final Future<void> Function(TripLedger trip) onReplace;
  final String Function(double v) money;
  /// 全书圈次，用于地点/高速费联想。
  final List<TripLedger> allRounds;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  static final _uuid = Uuid();
  late TripLedger _trip;

  @override
  void initState() {
    super.initState();
    _trip = widget.initial.copy();
  }

  Future<void> _commit() async {
    await widget.onReplace(_trip);
    if (mounted) setState(() {});
  }

  String _reconcileText(double value) {
    if (value > 0.000001) return '老板补你 ${widget.money(value)}';
    if (value < -0.000001) return '你退老板 ${widget.money(-value)}';
    return '无差额';
  }

  String _tollSubtitle(ExpenseItem item) {
    final parts = <String>[];
    if (item.tollCashAmount > 0.000001) {
      parts.add('现金 ${widget.money(item.tollCashAmount)}');
    }
    if (item.tollEtcAmount > 0.000001) {
      parts.add('ETC ${widget.money(item.tollEtcAmount)}');
    }
    final sum = widget.money(item.amount);
    if (parts.isEmpty) return '$sum · ${item.paymentSource.label}';
    return '$sum（${parts.join('，')}）· ${item.paymentSource.label}';
  }

  String _fuelSubtitle(ExpenseItem item) {
    final parts = <String>[widget.money(item.amount)];
    if (item.fuelKilograms > 0.000001) {
      final kg = item.fuelKilograms;
      final kgText = kg == kg.roundToDouble()
          ? '${kg.toInt()} kg'
          : '${kg.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')} kg';
      parts.add(kgText);
    }
    if (item.fuelUnitPrice > 0.000001) {
      parts.add('${widget.money(item.fuelUnitPrice)}/kg');
    }
    parts.add(item.paymentSource.label);
    return parts.join(' · ');
  }

  List<int> _expenseIndices(ExpenseCategory c) {
    final out = <int>[];
    for (var i = 0; i < _trip.expenses.length; i++) {
      if (_trip.expenses[i].category == c) out.add(i);
    }
    return out;
  }

  /// 与 Swift `splitMixedTollIfNeeded` 一致（按全局下标拆分现金+ETC）。
  Future<void> _splitMixedTollIfNeeded(int indexInCategory) async {
    final indices = _expenseIndices(ExpenseCategory.toll);
    if (indexInCategory >= indices.length) return;
    final globalIdx = indices[indexInCategory];
    final e = _trip.expenses[globalIdx];
    if (e.category != ExpenseCategory.toll) return;
    final c = e.tollCashAmount;
    final t = e.tollEtcAmount;
    if (c <= 0.000001 || t <= 0.000001) return;

    final base = e.title.trim();
    final titleCash = base.isEmpty ? '高速费（现金）' : '$base（现金）';
    final titleEtc = base.isEmpty ? '高速费（ETC）' : '$base（ETC）';
    final created = e.createdAt;
    final att = List<String>.from(e.attachments);

    final eCash = ExpenseItem(
      id: _uuid.v4(),
      category: ExpenseCategory.toll,
      title: titleCash,
      amount: c,
      paymentSource: PaymentSource.cash,
      isReimbursable: false,
      attachments: att,
      createdAt: created,
      tollCashAmount: c,
      tollEtcAmount: 0,
    );
    final eEtc = ExpenseItem(
      id: _uuid.v4(),
      category: ExpenseCategory.toll,
      title: titleEtc,
      amount: t,
      paymentSource: PaymentSource.etc,
      isReimbursable: false,
      attachments: att,
      createdAt: created,
      tollCashAmount: 0,
      tollEtcAmount: t,
    );
    _trip.expenses.removeAt(globalIdx);
    _trip.expenses.insert(globalIdx, eEtc);
    _trip.expenses.insert(globalIdx, eCash);
    setState(() {});
    await _commit();
  }

  Future<void> _editMeta() async {
    final r = await Navigator.push<TripMetaResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TripMetaEditorPage(start: _trip.startPlace, end: _trip.endPlace),
      ),
    );
    if (r == null) return;
    setState(() {
      _trip.startPlace = r.start;
      _trip.endPlace = r.end;
      _trip.title = makeTripTitle(r.start, r.end);
    });
    await _commit();
  }

  Future<void> _export() async {
    try {
      final result = await TripExcelExporter.exportTrip(_trip);
      // 与 Swift 一致：分享磁盘上的 .xlsx 文件 URL，避免 fromData 临时文件类型异常
      await Share.shareXFiles(
        [
          XFile(
            result.file.path,
            name: result.filename,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: result.filename,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _shareReconcileSummary() async {
    final sum = ProfitCalculator.calculate(_trip);
    final text = '''
【交账摘要】${_trip.title}
运费：${widget.money(sum.totalFreight)}
费用总：${widget.money(sum.totalExpense)}
利润：${widget.money(sum.netProfit)}
司机分成：${widget.money(sum.driverShare)}　老板分成：${widget.money(sum.ownerShare)}
司机应发：${widget.money(sum.driverWagePayable)}
出车费差额：${_reconcileText(sum.travelCashReconcile)}
交账净额：${_reconcileText(sum.cashNetSettlement)}
${sum.etcTollReconcileFee > 0.000001 ? 'ETC手续费(0.35%)：${widget.money(sum.etcTollReconcileFee)}\n' : ''}状态：${_trip.isReconciled ? '已交账' : '未交账'} / ${_trip.isSalarySettled ? '已发工资' : '未发工资'}
'''.trim();
    await Share.share(text, subject: '交账摘要 · ${_trip.title}');
  }

  Widget _itemWithThumbs({
    required String title,
    required String subtitle,
    required List<String> attachments,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
          onTap: onTap,
        ),
        if (attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AttachmentThumbStrip(
              names: attachments,
              compact: true,
              maxVisible: 3,
            ),
          ),
      ],
    );
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('路线（含运费/信息费）'),
              onTap: () {
                Navigator.pop(ctx);
                _openRouteEditor(null);
              },
            ),
            ListTile(
              title: const Text('油费'),
              onTap: () {
                Navigator.pop(ctx);
                _openExpense(ExpenseCategory.fuel, null);
              },
            ),
            ListTile(
              title: const Text('高速费'),
              onTap: () {
                Navigator.pop(ctx);
                _openExpense(ExpenseCategory.toll, null);
              },
            ),
            ListTile(
              title: const Text('其他费用'),
              onTap: () {
                Navigator.pop(ctx);
                _openExpense(ExpenseCategory.other, null);
              },
            ),
            ListTile(
              title: const Text('现金支取'),
              onTap: () {
                Navigator.pop(ctx);
                _openAdvance(null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRouteEditor(int? legIndex) async {
    final updated = await Navigator.push<TripLedger>(
      context,
      MaterialPageRoute(
        builder: (_) => RouteEditorPage(
          trip: _trip,
          legIndex: legIndex,
          allRounds: widget.allRounds,
        ),
      ),
    );
    if (updated != null) {
      setState(() => _trip = updated);
      await _commit();
    }
  }

  Future<void> _openExpense(ExpenseCategory cat, int? indexInCategory) async {
    if (cat == ExpenseCategory.toll && indexInCategory != null) {
      await _splitMixedTollIfNeeded(indexInCategory);
    }
    if (!mounted) return;
    final updated = await Navigator.push<TripLedger>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEditorPage(
          trip: _trip,
          category: cat,
          indexInCategory: indexInCategory,
          allRounds: widget.allRounds,
          money: widget.money,
        ),
      ),
    );
    if (updated != null) {
      setState(() => _trip = updated);
      await _commit();
    }
  }

  Future<void> _openAdvance(int? idx) async {
    final updated = await Navigator.push<TripLedger>(
      context,
      MaterialPageRoute(builder: (_) => AdvanceEditorPage(trip: _trip, advanceIndex: idx)),
    );
    if (updated != null) {
      setState(() => _trip = updated);
      await _commit();
    }
  }

  Future<void> _deleteRoute(int i) async {
    setState(() => _trip.routeLegs.removeAt(i));
    await _commit();
  }

  Future<void> _deleteExpenseGlobal(int globalIndex) async {
    setState(() => _trip.expenses.removeAt(globalIndex));
    await _commit();
  }

  Future<void> _deleteAdvance(int i) async {
    setState(() => _trip.cashAdvances.removeAt(i));
    await _commit();
  }

  @override
  Widget build(BuildContext context) {
    final sum = ProfitCalculator.calculate(_trip);
    return Scaffold(
      appBar: AppBar(
        title: Text(_trip.title),
        actions: [
          IconButton(
            tooltip: '分享交账摘要',
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareReconcileSummary,
          ),
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddSheet),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'meta') _editMeta();
              if (v == 'export') _export();
              if (v == 'share') _shareReconcileSummary();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'meta', child: Text('编辑圈次')),
              PopupMenuItem(value: 'share', child: Text('分享交账摘要')),
              PopupMenuItem(value: 'export', child: Text('导出 Excel')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionTitle('本圈结算'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _summaryBody(sum),
                style: const TextStyle(height: 1.35),
              ),
            ),
          ),
          TripStatCharts(summary: sum, money: widget.money),
          _sectionTitle('交账与工资状态'),
          SwitchListTile(
            title: const Text('是否已交账'),
            subtitle: Text(_trip.isReconciled ? '已交账' : '未交账'),
            value: _trip.isReconciled,
            onChanged: (v) async {
              setState(() => _trip.isReconciled = v);
              await _commit();
            },
          ),
          SwitchListTile(
            title: const Text('是否已工资结算'),
            subtitle: Text(_trip.isSalarySettled ? '已结算' : '未结算'),
            value: _trip.isSalarySettled,
            onChanged: (v) async {
              setState(() => _trip.isSalarySettled = v);
              await _commit();
            },
          ),
          _sectionTitle('路线明细（含运费、信息费）'),
          if (_trip.routeLegs.isEmpty)
            const ListTile(title: Text('暂无路线，点右上角新增'))
          else
            ...List.generate(_trip.routeLegs.length, (i) {
              final leg = _trip.routeLegs[i];
              final freightLabel = leg.freightExpression.isNotEmpty
                  ? '运费 ${widget.money(leg.freight)}（${leg.freightExpression}）'
                  : '运费 ${widget.money(leg.freight)}';
              return _itemWithThumbs(
                title: '${i + 1}. ${leg.loadPlace} -> ${leg.unloadPlace}',
                subtitle:
                    '$freightLabel  信息费 ${widget.money(leg.infoFee)} · ${leg.infoFeePaymentSource.label}',
                attachments: leg.attachments,
                onTap: () => _openRouteEditor(i),
                onDelete: () => _deleteRoute(i),
              );
            }),
          _sectionTitle('油费'),
          if (_expenseIndices(ExpenseCategory.fuel).isEmpty)
            const ListTile(title: Text('暂无油费'))
          else
            ..._expenseIndices(ExpenseCategory.fuel).asMap().entries.map((me) {
              final gi = me.value;
              final ii = me.key;
              final item = _trip.expenses[gi];
              return _itemWithThumbs(
                title: item.title,
                subtitle: _fuelSubtitle(item),
                attachments: item.attachments,
                onTap: () => _openExpense(ExpenseCategory.fuel, ii),
                onDelete: () => _deleteExpenseGlobal(gi),
              );
            }),
          _sectionTitle('高速费'),
          if (_expenseIndices(ExpenseCategory.toll).isEmpty)
            const ListTile(title: Text('暂无高速费'))
          else
            ..._expenseIndices(ExpenseCategory.toll).asMap().entries.map((me) {
              final gi = me.value;
              final ii = me.key;
              final item = _trip.expenses[gi];
              return _itemWithThumbs(
                title: item.title,
                subtitle: _tollSubtitle(item),
                attachments: item.attachments,
                onTap: () => _openExpense(ExpenseCategory.toll, ii),
                onDelete: () => _deleteExpenseGlobal(gi),
              );
            }),
          _sectionTitle('其他费用'),
          if (_expenseIndices(ExpenseCategory.other).isEmpty)
            const ListTile(title: Text('暂无其他费用'))
          else
            ..._expenseIndices(ExpenseCategory.other).asMap().entries.map((me) {
              final gi = me.value;
              final ii = me.key;
              final item = _trip.expenses[gi];
              final reimb = item.isReimbursable ? ' · 可报销' : '';
              return _itemWithThumbs(
                title: item.title,
                subtitle:
                    '${widget.money(item.amount)} · ${item.paymentSource.label}$reimb',
                attachments: item.attachments,
                onTap: () => _openExpense(ExpenseCategory.other, ii),
                onDelete: () => _deleteExpenseGlobal(gi),
              );
            }),
          _sectionTitle('现金支取'),
          if (_trip.cashAdvances.isEmpty)
            const ListTile(title: Text('暂无现金支取'))
          else
            ...List.generate(_trip.cashAdvances.length, (i) {
              final a = _trip.cashAdvances[i];
              return _itemWithThumbs(
                title: a.title,
                subtitle: widget.money(a.amount),
                attachments: a.attachments,
                onTap: () => _openAdvance(i),
                onDelete: () => _deleteAdvance(i),
              );
            }),
        ],
      ),
    );
  }

  String _summaryBody(ProfitSummary sum) {
    final etcLine = sum.etcTollReconcileFee > 0.000001
        ? '高速ETC对账手续费(0.35%)：${widget.money(sum.etcTollReconcileFee)}（已计入费用总与分成）\n'
        : '';
    final reimbLine = sum.reimbursableCashExpense > 0.000001
        ? '其中可报销(现金)：${widget.money(sum.reimbursableCashExpense)}'
            '（已计入费用总；你承担一半 ${widget.money(sum.reimbursableCashExpense - sum.reimbursableOwnerShare)}，'
            '老板承担一半 ${widget.money(sum.reimbursableOwnerShare)}）\n'
        : '';
    final travelLine = '出车费差额：${_reconcileText(sum.travelCashReconcile)}'
        '（现金花费 ${widget.money(sum.cashTotalExpense)} − 已支取 ${widget.money(sum.cashAdvances)}）\n';
    final wageLine = sum.reimbursableCashExpense > 0.000001
        ? '司机应发工资：${widget.money(sum.driverWagePayable)}'
            '（分成 ${widget.money(sum.driverShare)} + 老板还你 ${widget.money(sum.reimbursableOwnerShare)}）\n'
        : '';
    final fuelDetail = sum.fuelKilogramsTotal > 0.000001
        ? '油费 ${widget.money(sum.fuelExpense)}（气耗 ${_fmtKg(sum.fuelKilogramsTotal)} kg）'
        : '油费 ${widget.money(sum.fuelExpense)}';
    return '''
运费(总): ${widget.money(sum.totalFreight)}    利润: ${widget.money(sum.netProfit)}
费用(总): ${widget.money(sum.totalExpense)}    分成: 司机 ${widget.money(sum.driverShare)} / 老板 ${widget.money(sum.ownerShare)}

费用明细：$fuelDetail｜高速 ${widget.money(sum.tollExpense)}｜其他 ${widget.money(sum.otherExpense)}｜信息费 ${widget.money(sum.totalInfoFee)}
$etcLine$reimbLine$travelLine交账净额：${_reconcileText(sum.cashNetSettlement)}（仅出车费差额）
$wageLine''';
  }

  String _fmtKg(double kg) {
    if ((kg - kg.roundToDouble()).abs() < 0.000001) return kg.toInt().toString();
    final t = kg.toStringAsFixed(3);
    return t.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall),
      );
}
