import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// 管理端应用内更新（逻辑对齐主 App，文件名独立）。
class AdminAppUpdater {
  AdminAppUpdater._();

  static Future<void> openOrInstall(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw StateError('未配置下载地址');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw StateError('下载地址无效');
    }
    onProgress?.call(0);

    if (!kIsWeb && Platform.isAndroid && trimmed.toLowerCase().contains('.apk')) {
      await _downloadAndOpen(
        uri,
        fileName: 'truckledger-admin-update.apk',
        mimeType: 'application/vnd.android.package-archive',
        onProgress: onProgress,
      );
      return;
    }

    onProgress?.call(1);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) throw StateError('无法打开下载链接');
  }

  static Future<void> _downloadAndOpen(
    Uri uri, {
    required String fileName,
    String? mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    final req = http.Request('GET', uri);
    final streamed = await req.send().timeout(const Duration(minutes: 10));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw StateError('下载失败（${streamed.statusCode}）');
    }
    final total = streamed.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();
    onProgress?.call(1);
    await OpenFilex.open(file.path, type: mimeType);
  }
}
