import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用内更新：Android 下载 APK 并唤起安装；其它平台打开下载链接。
class AppUpdater {
  AppUpdater._();

  static Future<void> openOrInstall(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw StateError('未配置下载地址，请联系管理员');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw StateError('下载地址无效');
    }

    if (!kIsWeb && Platform.isAndroid && _looksLikeApk(trimmed)) {
      await _downloadAndInstallApk(uri, onProgress: onProgress);
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw StateError('无法打开下载链接');
    }
  }

  static bool _looksLikeApk(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.apk') || lower.contains('application/vnd.android');
  }

  static Future<void> _downloadAndInstallApk(
    Uri uri, {
    void Function(double progress)? onProgress,
  }) async {
    if (await Permission.requestInstallPackages.isDenied) {
      await Permission.requestInstallPackages.request();
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'truckledger-update.apk'));
    if (await file.exists()) {
      await file.delete();
    }

    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      final res = await client.send(req).timeout(const Duration(minutes: 5));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('下载失败（${res.statusCode}）');
      }
      final total = res.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }

    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw StateError(result.message.isNotEmpty ? result.message : '无法打开安装包');
    }
  }
}
