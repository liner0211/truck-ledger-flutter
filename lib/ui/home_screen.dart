import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:truck_ledger_editor/truck_ledger_editor.dart' show WageShareBar;

import '../models/trip_models.dart';
import '../services/ledger_backup_exporter.dart';
import '../services/ledger_backup_importer.dart';
import '../services/profit_calculator.dart';
import '../state/ledger_controller.dart';
import '../services/sync_service.dart';
import '../state/auth_controller.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'messages_screen.dart';
import 'monthly_summary_screen.dart';
import 'trip_detail_screen.dart';
import 'trip_meta_editor.dart';
import 'user_manual_screen.dart';

enum _RoundFilter { all, unreconciled, unpaidSalary }

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
    final auth = context.watch<AuthController>();
    final unread = auth.unreadMessages;
    final flags = auth.featureFlags;
    if (!ctrl.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final book = ctrl.book;
    double totalWageDue = 0;
    double totalWagePaid = 0;
    double unpaid = 0;
    String headerText;
    if (book.rounds.isEmpty) {
      headerText = '工资汇总：暂无圈次';
    } else {
      final summaries = book.rounds.map(ProfitCalculator.calculate).toList();
      totalWageDue =
          summaries.fold<double>(0, (a, s) => a + s.driverWagePayable);
      for (var i = 0; i < book.rounds.length; i++) {
        final round = book.rounds[i];
        final due = summaries[i].driverWagePayable;
        if (round.isSalarySettled) {
          totalWagePaid += due;
        }
        if (round.isReconciled && !round.isSalarySettled) {
          unpaid += due;
        }
      }
      headerText =
          '工资汇总（所有圈次）\n应得 ${ctrl.money(totalWageDue)} ｜ 已发 ${ctrl.money(totalWagePaid)} ｜ 未发 ${ctrl.money(unpaid)}（仅已交账）';
    }

    final q = _query.trim().toLowerCase();
    final filteredRounds = book.rounds.where((r) {
      final passFilter = switch (_filter) {
        _RoundFilter.all => true,
        _RoundFilter.unreconciled => !r.isReconciled,
        _RoundFilter.unpaidSalary => r.isReconciled && !r.isSalarySettled,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('圈次总览'),
        leading: IconButton(
          tooltip: ctrl.sortAscending ? '当前：开始时间升序，点击改为降序' : '当前：降序，点击改为升序',
          icon:
              Icon(ctrl.sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
          onPressed: () => context.read<LedgerController>().toggleSortOrder(),
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
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) async {
              if (v == 'export') {
                await _exportLedgerBackup(context);
                if (!context.mounted) return;
              }
              if (v == 'import') {
                await _pickAndImportLedger(context);
                if (!context.mounted) return;
              }
              if (v == 'account') {
                if (!context.mounted) return;
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
                );
              }
              if (v == 'messages') {
                if (!context.mounted) return;
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const MessagesScreen()),
                );
              }
              if (v == 'monthly') {
                if (!context.mounted) return;
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const MonthlySummaryScreen(),
                  ),
                );
              }
              if (v == 'manual') {
                if (!context.mounted) return;
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const UserManualScreen()),
                );
              }
              if (v == 'about') {
                if (!context.mounted) return;
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                );
              }
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[
                const PopupMenuItem(value: 'account', child: Text('账号与同步…')),
                const PopupMenuItem(value: 'monthly', child: Text('按月汇总…')),
                const PopupMenuItem(value: 'manual', child: Text('使用手册…')),
              ];
              if (flags.messages) {
                items.add(PopupMenuItem(
                  value: 'messages',
                  child: Text(unread > 0 ? '消息中心（$unread）…' : '消息中心…'),
                ));
              }
              if (flags.backupImport) {
                items.add(const PopupMenuItem(value: 'export', child: Text('导出备份…')));
                items.add(const PopupMenuItem(value: 'import', child: Text('导入账本…')));
              }
              items.add(const PopupMenuItem(value: 'about', child: Text('关于')));
              return items;
            },
          ),
          if (flags.messages && unread > 0)
            IconButton(
              tooltip: '未读消息',
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const MessagesScreen()),
                ).then((_) {
                  if (context.mounted) {
                    context.read<AuthController>().refreshInbox();
                  }
                });
              },
              icon: Badge(
                label: Text('$unread'),
                child: const Icon(Icons.mail_outline),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: ctrl.writeAllowed
                ? () => _addRound(context)
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('当前账号只读，无法新建圈次')),
                    );
                  },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SyncStatusBar(ctrl: ctrl),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      headerText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                    ),
                    if (book.rounds.isNotEmpty)
                      WageShareBar(
                        totalDue: totalWageDue,
                        paid: totalWagePaid,
                        unpaidReconciled: unpaid,
                        money: ctrl.money,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<_RoundFilter>(
              segments: const [
                ButtonSegment(value: _RoundFilter.all, label: Text('全部')),
                ButtonSegment(value: _RoundFilter.unreconciled, label: Text('未交账')),
                ButtonSegment(value: _RoundFilter.unpaidSalary, label: Text('待发工资')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              '每圈简写信息（点开查看详情）',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: filteredRounds.isEmpty
                ? Center(
                    child: Text(
                      book.rounds.isEmpty
                          ? '暂无圈次，点击右上角新建'
                          : (q.isNotEmpty
                              ? '无匹配圈次'
                              : '当前筛选下无圈次'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: filteredRounds.length,
                    itemBuilder: (context, index) {
                      final round = filteredRounds[index];
                      final sum = ProfitCalculator.calculate(round);
                      final reconcileText =
                          round.isReconciled ? '已交账' : '未交账';
                      final salaryText =
                          round.isSalarySettled ? '已工资结算' : '未工资结算';
                      return Dismissible(
                        key: ValueKey(round.id),
                        direction: DismissDirection.endToStart,
                        background: Builder(
                          builder: (ctx) {
                            final cs = Theme.of(ctx).colorScheme;
                            return Container(
                              color: cs.error,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: Icon(Icons.delete, color: cs.onError),
                            );
                          },
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
                        child: Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openDetail(context, round, ctrl),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          round.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.chevron_right,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _routePreview(round),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          height: 1.35,
                                        ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _pill(
                                          context,
                                          label: '司机应发',
                                          value: ctrl.money(sum.driverWagePayable),
                                          icon: Icons.account_circle_outlined,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _pill(
                                          context,
                                          label: '老板分成',
                                          value: ctrl.money(sum.ownerShare),
                                          icon: Icons.local_shipping_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _statusChip(
                                        context,
                                        text: reconcileText,
                                        ok: round.isReconciled,
                                      ),
                                      _statusChip(
                                        context,
                                        text: salaryText,
                                        ok: round.isSalarySettled,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
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
    if (round.routeLegs.isEmpty) return '路线：暂无';
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
    return '路线：${parts.join(' ｜ ')}';
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

  static Future<void> _exportLedgerBackup(BuildContext context) async {
    final ctrl = context.read<LedgerController>();
    final book = ctrl.book;
    if (book.rounds.isEmpty) {
      _snack(context, '暂无圈次，无需导出');
      return;
    }

    try {
      final result = await LedgerBackupExporter.exportBook(book);
      if (!context.mounted) return;
      await Share.shareXFiles(
        [XFile(result.file.path)],
        subject: result.filename,
        text: '卡车记账备份：${result.roundCount} 个圈次，${result.attachmentCount} 张附件',
      );
      if (!context.mounted) return;
      _snack(
        context,
        '已生成备份（${result.roundCount} 圈次，${result.attachmentCount} 张图）',
      );
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, '导出失败：$e');
    }
  }

  static Future<void> _pickAndImportLedger(BuildContext context) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'zip'],
      withData: true,
    );
    if (!context.mounted) return;
    if (picked == null || picked.files.isEmpty) return;

    final f = picked.files.single;
    final name = f.name.isNotEmpty ? f.name : (f.path ?? '');
    LedgerBackupBundle? bundle;
    if (f.bytes != null && f.bytes!.isNotEmpty) {
      bundle = await LedgerBackupImporter.fromFileBytes(f.bytes!, name);
    } else if (f.path != null) {
      bundle = await LedgerBackupImporter.fromFilePath(f.path!);
    }
    if (!context.mounted) return;
    if (bundle == null) {
      _snack(context, '无法识别备份文件（支持 .json 或本应用导出的 .zip）');
      return;
    }

    final incoming = bundle.book;
    final attCount = bundle.attachmentFiles.length;
    final attachmentFiles = bundle.attachmentFiles;
    if (!context.mounted) return;

    final n = incoming.rounds.length;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入账本'),
        content: Text(
          '已解析 $n 个圈次'
          '${attCount > 0 ? '，含 $attCount 张附件' : ''}。\n\n'
          '「合并」：追加到当前列表；若某圈次 id 与本地重复，会为该圈次及子项分配新 id。\n'
          '「覆盖」：清空本设备全部圈次并替换为文件内容（不可恢复）。\n\n'
          '${attCount > 0 ? 'ZIP 内附件将一并写入本机。\n' : '纯 JSON 不含附件时，图片需文件已在沙盒内才会显示。'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('合并'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );

    if (mode == null) return;
    if (!context.mounted) return;
    final ctrl = context.read<LedgerController>();

    Future<void> applyImport() async {
      if (attachmentFiles.isNotEmpty) {
        await LedgerBackupImporter.installAttachments(attachmentFiles);
      }
    }

    if (mode == 'merge') {
      await applyImport();
      await ctrl.importMerge(incoming);
      if (!context.mounted) return;
      _snack(
        context,
        '已合并 $n 个圈次${attCount > 0 ? '，写入 $attCount 张附件' : ''}',
      );
      return;
    }

    if (mode == 'replace') {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认覆盖？'),
          content: const Text('将删除本设备上的全部圈次与记账数据，且不可恢复。确定继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定覆盖'),
            ),
          ],
        ),
      );
      if (!context.mounted || ok != true) return;
      await applyImport();
      await ctrl.importReplace(incoming);
      if (!context.mounted) return;
      _snack(
        context,
        '已替换为导入账本（$n 个圈次${attCount > 0 ? '，$attCount 张附件' : ''}）',
      );
    }
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }
}

Widget _pill(
  BuildContext context, {
  required String label,
  required String value,
  required IconData icon,
}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cs.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _statusChip(
  BuildContext context, {
  required String text,
  required bool ok,
}) {
  final cs = Theme.of(context).colorScheme;
  final bg = ok ? cs.primaryContainer : cs.surfaceContainerHighest;
  final fg = ok ? cs.onPrimaryContainer : cs.onSurfaceVariant;
  final icon = ok ? Icons.check_circle_outline : Icons.radio_button_unchecked;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: cs.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
        ),
      ],
    ),
  );
}

class _SyncStatusBar extends StatefulWidget {
  const _SyncStatusBar({required this.ctrl});

  final LedgerController ctrl;

  @override
  State<_SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends State<_SyncStatusBar> {
  bool _hideSynced = false;
  SyncStatus? _lastStatus;

  @override
  void didUpdateWidget(covariant _SyncStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final status = widget.ctrl.syncStatus;
    if (status != _lastStatus) {
      _lastStatus = status;
      if (status == SyncStatus.synced) {
        _hideSynced = false;
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          if (widget.ctrl.syncStatus == SyncStatus.synced) {
            setState(() => _hideSynced = true);
          }
        });
      } else {
        _hideSynced = false;
      }
    }
  }

  Future<void> _retrySync() async {
    final msg = await widget.ctrl.syncWithCloud();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openAccount() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final status = ctrl.syncStatus;
    if (status == SyncStatus.idle) {
      return const SizedBox.shrink();
    }
    if (status == SyncStatus.synced && _hideSynced) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    String text;
    VoidCallback? onTap;
    switch (status) {
      case SyncStatus.dirty:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        text = '有未上传修改 · 点此同步';
        onTap = _retrySync;
        break;
      case SyncStatus.pending:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        text = ctrl.syncProgressMessage.isNotEmpty
            ? ctrl.syncProgressMessage
            : '正在同步…';
        onTap = null;
        break;
      case SyncStatus.conflict:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        text = '同步冲突 — 请到「账号与同步」处理';
        onTap = _openAccount;
        break;
      case SyncStatus.error:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        text = '同步失败 · 点此重试';
        onTap = _retrySync;
        break;
      case SyncStatus.synced:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        text = '已同步';
        onTap = _openAccount;
        break;
      case SyncStatus.idle:
        return const SizedBox.shrink();
    }
    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (status == SyncStatus.pending)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  else
                    Icon(
                      status == SyncStatus.conflict || status == SyncStatus.error
                          ? Icons.warning_amber
                          : status == SyncStatus.dirty
                              ? Icons.cloud_upload_outlined
                              : Icons.cloud_done_outlined,
                      size: 16,
                      color: fg,
                    ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: fg))),
                  if (status == SyncStatus.pending && ctrl.syncProgress != null)
                    Text(
                      '${(ctrl.syncProgress! * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 12, color: fg),
                    )
                  else if (status == SyncStatus.dirty || status == SyncStatus.error)
                    IconButton(
                      tooltip: '账号与同步',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(Icons.manage_accounts_outlined, size: 18, color: fg),
                      onPressed: _openAccount,
                    ),
                ],
              ),
              if (status == SyncStatus.pending) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: ctrl.syncProgress, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
