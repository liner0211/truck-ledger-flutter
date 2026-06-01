import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trip_models.dart';
import '../services/ledger_backup_exporter.dart';
import '../services/ledger_backup_importer.dart';
import '../services/profit_calculator.dart';
import '../state/ledger_controller.dart';
import 'about_screen.dart';
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
          summaries.fold<double>(0, (a, s) => a + s.driverWagePayable);
      var totalWagePaid = 0.0;
      for (var i = 0; i < book.rounds.length; i++) {
        if (book.rounds[i].isSalarySettled) {
          totalWagePaid += summaries[i].driverWagePayable;
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
          icon:
              Icon(ctrl.sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
          onPressed: () => context.read<LedgerController>().toggleSortOrder(),
        ),
        actions: [
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
              if (v == 'about') {
                if (!context.mounted) return;
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('导出备份…')),
              PopupMenuItem(value: 'import', child: Text('导入账本…')),
              PopupMenuItem(value: 'about', child: Text('关于')),
            ],
          ),
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
            child: Text(
              '每圈简写信息（点开查看详情）',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          Expanded(
            child: book.rounds.isEmpty
                ? const Center(child: Text('暂无圈次，点击右上角新建'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
