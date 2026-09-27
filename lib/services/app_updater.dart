import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用内更新：优先本地下载并安装（带进度）；无法安装时再打开外链。
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

    onProgress?.call(0);

    if (!kIsWeb && Platform.isAndroid && _looksLikeApk(trimmed)) {
      await _downloadAndOpen(
        uri,
        fileName: 'truckledger-update.apk',
        mimeType: 'application/vnd.android.package-archive',
        onProgress: onProgress,
        beforeOpen: () async {
          if (await Permission.requestInstallPackages.isDenied) {
            await Permission.requestInstallPackages.request();
          }
        },
      );
      return;
    }

    if (!kIsWeb && Platform.isIOS && _looksLikeIpa(trimmed)) {
      await _downloadAndOpen(
        uri,
        fileName: 'truckledger-update.ipa',
        mimeType: 'application/octet-stream',
        onProgress: onProgress,
      );
      return;
    }

    // 其它情况：仍尝试下载以便展示进度，然后交给系统打开
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final name = p.basename(uri.path);
      final safeName = name.isEmpty || !name.contains('.')
          ? (Platform.isAndroid ? 'truckledger-update.bin' : 'truckledger-update.ipa')
          : name;
      try {
        await _downloadAndOpen(
          uri,
          fileName: safeName,
          mimeType: null,
          onProgress: onProgress,
        );
        return;
      } catch (_) {
        // 回退外链
      }
    }

    onProgress?.call(1);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw StateError('无法打开下载链接');
    }
  }

  static bool _looksLikeApk(String url) {
    final lower = url.toLowerCase();
    // 生产 downloads 常见无扩展名的 latest 链接，也按 APK 处理
    return lower.contains('.apk') ||
        lower.contains('truckledger-latest') ||
        (lower.contains('/downloads/') && lower.contains('truckledger'));
  }

  static bool _looksLikeIpa(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.ipa');
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
      final res = await client.send(req).timeout(const Duration(minutes: 10));
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
            // 未知总长：按已收字节缓慢逼近 0.9，避免一直 0%
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
      // iOS 未签名 IPA 可能无法直接安装：回退浏览器/分享
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw StateError(result.message.isNotEmpty ? result.message : '无法打开安装包');
      }
    }
  }
}
