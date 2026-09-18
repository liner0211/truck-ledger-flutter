import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/trip_models.dart';
import 'attachment_store.dart';
import 'api_http_client.dart';
import 'auth_api.dart';
import 'ledger_backup_exporter.dart';

class RemoteLedger {
  RemoteLedger({
    required this.book,
    required this.updatedAt,
    required this.revision,
  });

  final LedgerBook book;
  final int updatedAt;
  final int revision;
}

class SyncConflictException implements Exception {
  SyncConflictException(this.server);

  final RemoteLedger server;

  @override
  String toString() => '账本版本冲突';
}

enum SyncStatus { idle, synced, dirty, pending, conflict, error }

/// 同步进度（fraction 为 null 表示不确定进度）。
class SyncProgress {
  const SyncProgress({this.fraction, this.message = ''});

  final double? fraction;
  final String message;

  static const idle = SyncProgress();
}

class SyncService {
  SyncService({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  String _url(String path) {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$root$path';
  }

  Map<String, String> _authHeaders() => {
        'Authorization': 'Bearer $token',
      };

  RemoteLedger _parseLedger(Map<String, dynamic> m) {
    final updatedAt = (m['updated_at'] as num?)?.toInt() ?? 0;
    final revision = (m['revision'] as num?)?.toInt() ?? 0;
    final book = LedgerBook.fromJson(m);
    return RemoteLedger(book: book, updatedAt: updatedAt, revision: revision);
  }

  Future<RemoteLedger> pull() async {
    final res = await apiHttpClient
        .get(
          Uri.parse(_url('/api/ledger')),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录', statusCode: 401);
    }
    if (res.statusCode != 200) {
      throw ApiException('拉取失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    return _parseLedger(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<({int updatedAt, int revision})> push(
    LedgerBook book, {
    required int baseRevision,
    bool force = false,
  }) async {
    final res = await apiHttpClient
        .put(
          Uri.parse(_url('/api/ledger')),
          headers: {
            ..._authHeaders(),
            'Content-Type': 'application/json',
            if (!force) 'If-Match': '$baseRevision',
          },
          body: jsonEncode({
            'rounds': book.toJson()['rounds'],
            'base_revision': baseRevision,
            if (force) 'force': true,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录', statusCode: 401);
    }
    if (res.statusCode == 409) {
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      final serverMap = (m['server'] as Map?)?.cast<String, dynamic>() ?? m;
      throw SyncConflictException(_parseLedger(serverMap));
    }
    if (res.statusCode == 403) {
      throw ApiException(_detail(res) ?? '无权写入（可能已到期只读）', statusCode: 403);
    }
    if (res.statusCode != 200) {
      throw ApiException(_detail(res) ?? '上传失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      updatedAt: (m['updated_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      revision: (m['revision'] as num?)?.toInt() ?? baseRevision + 1,
    );
  }

  String? _detail(http.Response res) {
    try {
      final m = jsonDecode(res.body);
      if (m is Map && m['detail'] != null) return m['detail'].toString();
    } catch (_) {}
    return null;
  }

  Future<Set<String>> listRemoteAttachments() async {
    final res = await apiHttpClient
        .get(
          Uri.parse(_url('/api/attachments')),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('获取附件列表失败（${res.statusCode}）');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final files = m['files'];
    if (files is! List) return {};
    return files.map((e) => e.toString()).toSet();
  }

  Future<void> uploadAttachment(String filename) async {
    final file = await AttachmentStore.fileFor(filename);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse(_url('/api/attachments/$filename')),
    );
    req.headers.addAll(_authHeaders());
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await apiHttpClient.send(req).timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw ApiException('上传附件 $filename 失败（${res.statusCode}）');
    }
  }

  Future<void> downloadAttachment(String filename) async {
    final res = await apiHttpClient
        .get(
          Uri.parse(_url('/api/attachments/$filename')),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode == 404) return;
    if (res.statusCode != 200) {
      throw ApiException('下载附件 $filename 失败（${res.statusCode}）');
    }
    await AttachmentStore.saveDownloadedJpeg(filename, res.bodyBytes);
  }

  Future<int> uploadMissingAttachments(
    LedgerBook book, {
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final needed = LedgerBackupExporter.collectAttachmentNames(book);
    if (needed.isEmpty) {
      onProgress?.call(const SyncProgress(fraction: 1, message: '无附件需上传'));
      return 0;
    }
    onProgress?.call(const SyncProgress(fraction: 0.05, message: '检查云端附件…'));
    final remote = await listRemoteAttachments();
    final toUpload = <String>[];
    for (final name in needed) {
      if (remote.contains(name)) continue;
      final file = await AttachmentStore.fileFor(name);
      if (!file.existsSync()) continue;
      toUpload.add(name);
    }
    if (toUpload.isEmpty) {
      onProgress?.call(const SyncProgress(fraction: 0.4, message: '附件已齐全'));
      return 0;
    }
    var uploaded = 0;
    for (var i = 0; i < toUpload.length; i++) {
      final name = toUpload[i];
      onProgress?.call(SyncProgress(
        fraction: 0.1 + 0.5 * (i / toUpload.length),
        message: '上传附件 ${i + 1}/${toUpload.length}',
      ));
      await uploadAttachment(name);
      uploaded++;
      onProgress?.call(SyncProgress(
        fraction: 0.1 + 0.5 * ((i + 1) / toUpload.length),
        message: '已上传附件 ${i + 1}/${toUpload.length}',
      ));
    }
    return uploaded;
  }

  Future<int> downloadMissingAttachments(
    LedgerBook book, {
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final needed = LedgerBackupExporter.collectAttachmentNames(book).toList();
    if (needed.isEmpty) {
      onProgress?.call(const SyncProgress(fraction: 1, message: '无附件需下载'));
      return 0;
    }
    final toDownload = <String>[];
    for (final name in needed) {
      final file = await AttachmentStore.fileFor(name);
      if (file.existsSync()) continue;
      toDownload.add(name);
    }
    if (toDownload.isEmpty) {
      onProgress?.call(const SyncProgress(fraction: 0.9, message: '本地附件已齐全'));
      return 0;
    }
    var downloaded = 0;
    for (var i = 0; i < toDownload.length; i++) {
      final name = toDownload[i];
      onProgress?.call(SyncProgress(
        fraction: 0.2 + 0.7 * (i / toDownload.length),
        message: '下载附件 ${i + 1}/${toDownload.length}',
      ));
      await downloadAttachment(name);
      final again = await AttachmentStore.fileFor(name);
      if (again.existsSync()) downloaded++;
      onProgress?.call(SyncProgress(
        fraction: 0.2 + 0.7 * ((i + 1) / toDownload.length),
        message: '已下载附件 ${i + 1}/${toDownload.length}',
      ));
    }
    return downloaded;
  }

  Future<({int updatedAt, int revision})> pushFull(
    LedgerBook book, {
    required int baseRevision,
    bool force = false,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    onProgress?.call(const SyncProgress(fraction: 0.02, message: '准备上传…'));
    await uploadMissingAttachments(book, onProgress: onProgress);
    onProgress?.call(const SyncProgress(fraction: 0.75, message: '上传账本…'));
    final result = await push(book, baseRevision: baseRevision, force: force);
    try {
      await AttachmentStore.deleteOrphans(
        LedgerBackupExporter.collectAttachmentNames(book),
      );
    } catch (_) {}
    onProgress?.call(const SyncProgress(fraction: 1, message: '上传完成'));
    return result;
  }

  Future<RemoteLedger> pullFull({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    onProgress?.call(const SyncProgress(fraction: 0.05, message: '拉取账本…'));
    final remote = await pull();
    onProgress?.call(const SyncProgress(fraction: 0.35, message: '下载附件…'));
    await downloadMissingAttachments(remote.book, onProgress: onProgress);
    try {
      await AttachmentStore.deleteOrphans(
        LedgerBackupExporter.collectAttachmentNames(remote.book),
      );
    } catch (_) {}
    onProgress?.call(const SyncProgress(fraction: 1, message: '拉取完成'));
    return remote;
  }
}
