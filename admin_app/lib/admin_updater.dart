import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// 管理端应用内更新：本地下载 + 进度回调 + 打开安装包（默认不走浏览器）。
class AdminAppUpdater {
  AdminAppUpdater._();

  static Future<void> openOrInstall(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw StateError('未配置下载地址，请到控制面填写管理端下载链接');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw StateError('下载地址无效');
    }

    onProgress?.call(0);

    // Web 无法可靠旁路浏览器安装，只能外链
    if (kIsWeb) {
      onProgress?.call(1);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('无法打开下载链接');
      return;
    }

    final fileName = _suggestFileName(uri, trimmed);
    final mime = _mimeFor(fileName);

    try {
      await _downloadAndOpen(
        uri,
        fileName: fileName,
        mimeType: mime,
        onProgress: onProgress,
        beforeOpen: () async {
          if (Platform.isAndroid && fileName.toLowerCase().endsWith('.apk')) {
            if (await Permission.requestInstallPackages.isDenied) {
              await Permission.requestInstallPackages.request();
            }
          }
        },
      );
      return;
    } catch (_) {
      // 回退外链
    }

    onProgress?.call(1);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw StateError('无法打开下载链接');
    }
  }

  static String _suggestFileName(Uri uri, String url) {
    final base = p.basename(uri.path);
    final lower = url.toLowerCase();
    if (base.isNotEmpty && base.contains('.')) {
      return base.contains('..') ? 'truckledger-admin-update.bin' : base;
    }
    if (Platform.isAndroid || _looksLikeApk(lower)) {
      return 'truckledger-admin-update.apk';
    }
    if (Platform.isIOS || lower.contains('.ipa')) {
      return 'truckledger-admin-update.ipa';
    }
    if (Platform.isLinux || lower.contains('.deb') || lower.contains('.appimage')) {
      return lower.contains('.appimage')
          ? 'truckledger-admin-update.AppImage'
          : 'truckledger-admin-update.deb';
    }
    if (Platform.isWindows || lower.contains('.exe') || lower.contains('.msix')) {
      return lower.contains('.msix')
          ? 'truckledger-admin-update.msix'
          : 'truckledger-admin-update.exe';
    }
    return 'truckledger-admin-update.bin';
  }

  static bool _looksLikeApk(String lower) {
    return lower.contains('.apk') ||
        lower.contains('admin-latest') ||
        lower.contains('truckledger-admin') ||
        (lower.contains('/downloads/') && lower.contains('admin'));
  }

  static String? _mimeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.apk')) {
      return 'application/vnd.android.package-archive';
    }
    if (lower.endsWith('.deb')) return 'application/vnd.debian.binary-package';
    if (lower.endsWith('.exe')) return 'application/vnd.microsoft.portable-executable';
    if (lower.endsWith('.msix')) return 'application/msix';
    return 'application/octet-stream';
  }

  static Future<void> _downloadAndOpen(
    Uri uri, {
    required String fileName,
    required String? mimeType,
    void Function(double progress)? onProgress,
    Future<void> Function()? beforeOpen,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    if (await file.exists()) {
      await file.delete();
    }

    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      final res = await client.send(req).timeout(const Duration(minutes: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('下载失败（${res.statusCode}）');
      }
      final total = res.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) {
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 0.99));
          } else {
            onProgress((1 - (1 / (1 + received / (2 * 1024 * 1024)))).clamp(0.0, 0.9));
          }
        }
      }
      await sink.close();
      onProgress?.call(1);
    } finally {
      client.close();
    }

    if (beforeOpen != null) {
      await beforeOpen();
    }

    final result = mimeType == null
        ? await OpenFilex.open(file.path)
        : await OpenFilex.open(file.path, type: mimeType);
    if (result.type != ResultType.done) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw StateError(
          result.message.isNotEmpty ? result.message : '无法打开安装包',
        );
      }
    }
  }
}
