import 'package:flutter/material.dart';

import '../admin_updater.dart';

/// 全屏对话框展示下载进度（与司机端一致，不走浏览器）。
Future<void> runAdminUpdateWithProgress(BuildContext context, String url) async {
  final progress = ValueNotifier<double>(0);
  var closed = false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在更新管理端'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, p, _) {
              final pct = (p * 100).clamp(0, 100);
              final label = p <= 0
                  ? '准备下载…'
                  : p >= 1
                      ? '下载完成，正在打开安装包…'
                      : '下载中 ${pct.toStringAsFixed(0)}%';
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    minHeight: 8,
                    value: p > 0 && p < 1 ? p : (p >= 1 ? 1 : null),
                  ),
                  const SizedBox(height: 12),
                  Text(label, textAlign: TextAlign.center),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  try {
    await AdminAppUpdater.openOrInstall(
      url,
      onProgress: (p) {
        progress.value = p;
      },
    );
  } finally {
    if (context.mounted && !closed) {
      closed = true;
      Navigator.of(context, rootNavigator: true).pop();
    }
    await Future<void>.delayed(Duration.zero);
    progress.dispose();
  }
}
