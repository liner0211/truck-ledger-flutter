import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ledger_backup_exporter.dart';
import '../services/ledger_backup_importer.dart';
import '../state/ledger_controller.dart';

/// 导出 / 导入账本（圈次页与「我的」共用）。
class LedgerBackupActions {
  LedgerBackupActions._();

  static Future<void> export(BuildContext context) async {
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

  static Future<void> import(BuildContext context) async {
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
