import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip_models.dart';
import '../services/profit_calculator.dart';
import '../services/sync_service.dart';
import '../services/trip_date.dart';
import '../state/ledger_controller.dart';
import 'account_screen.dart';
import 'trip_detail_screen.dart';
import 'trip_meta_editor.dart';

enum _RoundFilter { all, inProgress, reconciled }

/// 底部 Tab「圈次」：列表 + 筛选 + FAB。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _RoundFilter _filter = _RoundFilter.all;
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LedgerController>();
    if (!ctrl.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final book = ctrl.book;
    final q = _query.trim().toLowerCase();
    final filteredRounds = book.rounds.where((r) {
      final passFilter = switch (_filter) {
        _RoundFilter.all => true,
        _RoundFilter.inProgress => !r.isReconciled,
        _RoundFilter.reconciled => r.isReconciled,
      };
      if (!passFilter) return false;
      if (q.isEmpty) return true;
      final hay = [
        r.title,
        r.startPlace,
        r.endPlace,
        _routePreview(r),
        for (final leg in r.routeLegs) ...[leg.loadPlace, leg.unloadPlace],
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('圈次'),
        centerTitle: true,
        leadingWidth: 96,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _SyncChip(
              ctrl: ctrl,
              onOpenSync: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
                );
              },
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _searchOpen ? '关闭搜索' : '搜索圈次',
            icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _searchCtrl.clear();
                  _query = '';
                }
              });
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: ctrl.writeAllowed
            ? () => _addRound(context)
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('当前账号只读，无法新建圈次')),
                );
              },
        icon: const Icon(Icons.add),
        label: const Text('记一圈'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ctrl.syncStatus == SyncStatus.pending ||
              ctrl.syncStatus == SyncStatus.conflict ||
              ctrl.syncStatus == SyncStatus.error ||
              ctrl.syncStatus == SyncStatus.dirty)
            _SyncBanner(ctrl: ctrl),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _filter == _RoundFilter.all,
                  onSelected: (_) => setState(() => _filter = _RoundFilter.all),
                ),
                ChoiceChip(
                  label: const Text('进行中'),
                  selected: _filter == _RoundFilter.inProgress,
                  onSelected: (_) =>
                      setState(() => _filter = _RoundFilter.inProgress),
                ),
                ChoiceChip(
                  label: const Text('已交账'),
                  selected: _filter == _RoundFilter.reconciled,
                  onSelected: (_) =>
                      setState(() => _filter = _RoundFilter.reconciled),
                ),
              ],
            ),
          ),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜索标题、装卸地、路线…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          Expanded(
            child: filteredRounds.isEmpty
                ? Center(
                    child: Text(
                      book.rounds.isEmpty
                          ? '暂无圈次，点下方「记一圈」开始'
                          : (q.isNotEmpty ? '无匹配圈次' : '当前筛选下无圈次'),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
                    itemCount: filteredRounds.length,
                    itemBuilder: (context, index) {
                      final round = filteredRounds[index];
                      final sum = ProfitCalculator.calculate(round);
                      return Dismissible(
                        key: ValueKey(round.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: cs.error,
                          child: Icon(Icons.delete, color: cs.onError),
                        ),
                        confirmDismiss: (_) async {
                          final shouldDelete = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('是否删除圈次'),
                              content: Text('确定删除「${round.title}」吗？删除后不可恢复。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (shouldDelete != true) return false;
                          if (!context.mounted) return false;
                          final c = context.read<LedgerController>();
                          final idx =
                              c.book.rounds.indexWhere((r) => r.id == round.id);
                          if (idx < 0) return false;
                          await c.deleteTripAt(idx);
                          return true;
                        },
                        child: _TripCard(
                          round: round,
                          sum: sum,
                          money: ctrl.money,
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

  static String _routePreview(TripLedger round) {
    if (round.routeLegs.isEmpty) {
      final a = round.startPlace.trim();
      final b = round.endPlace.trim();
      if (a.isEmpty && b.isEmpty) return '路线：暂无';
      if (a.isEmpty) return b;
      if (b.isEmpty) return a;
      return '$a → $b';
    }
    final parts = round.routeLegs
        .map((l) {
          final a = l.loadPlace.trim();
          final b = l.unloadPlace.trim();
          if (a.isEmpty && b.isEmpty) return null;
          if (a.isEmpty) return b;
          if (b.isEmpty) return a;
          return '$a → $b';
        })
        .whereType<String>()
        .toList();
    if (parts.isEmpty) return '路线：暂无';
    return parts.join(' ｜ ');
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
          allRounds: ctrl.book.rounds,
          onReplace: (updated) => ctrl.replaceTrip(updated),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.round,
    required this.sum,
    required this.money,
    required this.onTap,
  });

  final TripLedger round;
  final ProfitSummary sum;
  final String Function(double) money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = TripDate.sortDate(round);
    final dateText =
        '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final wagePaid = round.isSalarySettled;
    final amber = const Color(0xFFE8A317);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      round.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(
                    text: round.isReconciled ? '已交账' : '未交账',
                    ok: round.isReconciled,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                dateText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              if (_HomeScreenState._routePreview(round) != '路线：暂无') ...[
                const SizedBox(height: 4),
                Text(
                  _HomeScreenState._routePreview(round),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '净利 ${money(sum.netProfit)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      wagePaid
                          ? '工资 ${money(sum.driverWagePayable)} · 已发'
                          : '工资 ${money(sum.driverWagePayable)} · 未发',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: wagePaid ? cs.onSurfaceVariant : amber,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = ok ? cs.primaryContainer : const Color(0xFFFFF3E0);
    final fg = ok ? cs.onPrimaryContainer : const Color(0xFFE65100);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: dark
            ? (ok ? cs.primaryContainer : cs.surfaceContainerHighest)
            : bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: dark ? (ok ? cs.onPrimaryContainer : cs.onSurfaceVariant) : fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.ctrl, required this.onOpenSync});

  final LedgerController ctrl;
  final VoidCallback onOpenSync;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = ctrl.syncStatus;
    String label;
    Color bg;
    Color fg;
    switch (status) {
      case SyncStatus.synced:
      case SyncStatus.idle:
        label = '已同步';
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
      case SyncStatus.dirty:
        label = '待上传';
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
      case SyncStatus.pending:
        label = '同步中';
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
      case SyncStatus.conflict:
        label = '冲突';
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
      case SyncStatus.error:
        label = '失败';
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
    }
    return ActionChip(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      label: Text(label, style: TextStyle(fontSize: 12, color: fg)),
      backgroundColor: bg,
      side: BorderSide.none,
      onPressed: onOpenSync,
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.ctrl});

  final LedgerController ctrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = ctrl.syncStatus;
    late Color bg;
    late Color fg;
    late String text;
    VoidCallback? onTap;

    switch (status) {
      case SyncStatus.dirty:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        text = '有未上传修改 · 点此同步';
        onTap = () async {
          final msg = await ctrl.syncWithCloud();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        };
      case SyncStatus.pending:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        text = ctrl.syncProgressMessage.isNotEmpty
            ? ctrl.syncProgressMessage
            : '正在同步…';
        onTap = null;
      case SyncStatus.conflict:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        text = '同步冲突 — 请到「我的 → 同步与冲突」处理';
        onTap = () {
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
          );
        };
      case SyncStatus.error:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        text = '同步失败 · 点此重试';
        onTap = () async {
          final msg = await ctrl.syncWithCloud();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        };
      case SyncStatus.synced:
      case SyncStatus.idle:
        return const SizedBox.shrink();
    }

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (status == SyncStatus.pending)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else
                Icon(Icons.info_outline, size: 16, color: fg),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: fg))),
            ],
          ),
        ),
      ),
    );
  }
}
