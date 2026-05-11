import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip_models.dart';
import '../services/profit_calculator.dart';
import '../state/ledger_controller.dart';
import 'trip_detail_screen.dart';
import 'trip_meta_editor.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LedgerController>();
    if (!ctrl.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final book = ctrl.book;
    String headerText;
    if (book.rounds.isEmpty) {
      headerText = '工资汇总：暂无圈次';
    } else {
      final summaries = book.rounds.map(ProfitCalculator.calculate).toList();
      final totalWageDue =
          summaries.fold<double>(0, (a, s) => a + s.driverShare);
      var totalWagePaid = 0.0;
      for (var i = 0; i < book.rounds.length; i++) {
        if (book.rounds[i].isSalarySettled) {
          totalWagePaid += summaries[i].driverShare;
        }
      }
      final unpaid = totalWageDue - totalWagePaid;
      headerText =
          '工资汇总（所有圈次）\n应得 ${ctrl.money(totalWageDue)} ｜ 已发 ${ctrl.money(totalWagePaid)} ｜ 未发 ${ctrl.money(unpaid)}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('圈次总览'),
        leading: IconButton(
          tooltip: ctrl.sortAscending ? '当前：开始时间升序，点击改为降序' : '当前：降序，点击改为升序',
          icon: Icon(ctrl.sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
          onPressed: () => context.read<LedgerController>().toggleSortOrder(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addRound(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  headerText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('每圈简写信息（点开查看详情）',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
          ),
          Expanded(
            child: book.rounds.isEmpty
                ? const Center(child: Text('暂无圈次，点击右上角新建'))
                : ListView.builder(
                    itemCount: book.rounds.length,
                    itemBuilder: (context, index) {
                      final round = book.rounds[index];
                      final sum = ProfitCalculator.calculate(round);
                      final reconcileText =
                          round.isReconciled ? '已交账' : '未交账';
                      final salaryText =
                          round.isSalarySettled ? '已工资结算' : '未工资结算';
                      return Dismissible(
                        key: ValueKey(round.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red.shade700,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          final c = context.read<LedgerController>();
                          final idx =
                              c.book.rounds.indexWhere((r) => r.id == round.id);
                          if (idx < 0) return false;
                          await c.deleteTripAt(idx);
                          return true;
                        },
                        child: ListTile(
                          title: Text(round.title),
                          subtitle: Text(
                            '分成：司机 ${ctrl.money(sum.driverShare)} / 老板 ${ctrl.money(sum.ownerShare)}\n'
                            '状态：$reconcileText ｜ $salaryText',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openDetail(context, round, ctrl),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addRound(BuildContext context) async {
    final r = await Navigator.push<TripMetaResult>(
      context,
      MaterialPageRoute(
        builder: (_) => const TripMetaEditorPage(start: '', end: ''),
      ),
    );
    if (r == null || !context.mounted) return;
    await context.read<LedgerController>().addRound(r.start, r.end);
  }

  Future<void> _openDetail(
    BuildContext context,
    TripLedger round,
    LedgerController ctrl,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TripDetailScreen(
          initial: round.copy(),
          money: ctrl.money,
          onReplace: (updated) => ctrl.replaceTrip(updated),
        ),
      ),
    );
  }
}
