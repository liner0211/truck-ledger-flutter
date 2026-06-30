import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/trip_models.dart';
import 'attachment_store.dart';
import 'api_http_client.dart';
import 'auth_api.dart';
import 'ledger_backup_exporter.dart';

class RemoteLedger {
  RemoteLedger({required this.book, required this.updatedAt});

  final LedgerBook book;
  final int updatedAt;
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
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final updatedAt = (m['updated_at'] as num?)?.toInt() ?? 0;
    final book = LedgerBook.fromJson(m);
    return RemoteLedger(book: book, updatedAt: updatedAt);
  }

  Future<int> push(LedgerBook book) async {
    final res = await apiHttpClient
        .put(
          Uri.parse(_url('/api/ledger')),
          headers: {
            ..._authHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'rounds': book.toJson()['rounds']}),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录', statusCode: 401);
    }
    if (res.statusCode != 200) {
      throw ApiException('上传失败（${res.statusCode}）', statusCode: res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['updated_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
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
    final dest = await AttachmentStore.fileFor(filename);
    await dest.writeAsBytes(res.bodyBytes, flush: true);
  }

  Future<int> uploadMissingAttachments(LedgerBook book) async {
    final needed = LedgerBackupExporter.collectAttachmentNames(book);
    if (needed.isEmpty) return 0;
    final remote = await listRemoteAttachments();
    var uploaded = 0;
    for (final name in needed) {
      if (remote.contains(name)) continue;
      final file = await AttachmentStore.fileFor(name);
      if (!file.existsSync()) continue;
      await uploadAttachment(name);
      uploaded++;
    }
    return uploaded;
  }

  Future<int> downloadMissingAttachments(LedgerBook book) async {
    final needed = LedgerBackupExporter.collectAttachmentNames(book);
    if (needed.isEmpty) return 0;
    var downloaded = 0;
    for (final name in needed) {
      final file = await AttachmentStore.fileFor(name);
      if (file.existsSync()) continue;
      await downloadAttachment(name);
      final again = await AttachmentStore.fileFor(name);
      if (again.existsSync()) downloaded++;
    }
    return downloaded;
  }

  Future<int> pushFull(LedgerBook book) async {
    final updatedAt = await push(book);
    await uploadMissingAttachments(book);
    return updatedAt;
  }

  Future<RemoteLedger> pullFull() async {
    final remote = await pull();
    await downloadMissingAttachments(remote.book);
    return remote;
  }
}
