import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 与 Swift `AttachmentStore` 一致：`Documents/attachments/` 下存 JPEG，文件名为 UUID。
/// 同步另存缩略图于 `attachments/thumbs/`。
/// 管理端可通过 [userScope] 隔离不同用户的本地缓存目录。
class AttachmentStore {
  AttachmentStore._();

  static Directory? _dir;
  static Directory? _thumbDir;
  static String? _userScope;

  /// 例如 `admin_12`；设为 null 时使用默认 `attachments/`（主 App）。
  static String? get userScope => _userScope;

  static set userScope(String? value) {
    final next = (value == null || value.isEmpty) ? null : value;
    if (_userScope == next) return;
    _userScope = next;
    _dir = null;
    _thumbDir = null;
  }

  static Future<Directory> attachmentsDirectory() async {
    if (_dir != null) return _dir!;
    final documents = await getApplicationDocumentsDirectory();
    final path = _userScope == null
        ? p.join(documents.path, 'attachments')
        : p.join(documents.path, 'attachments', _userScope!);
    _dir = Directory(path);
    if (!_dir!.existsSync()) {
      _dir!.createSync(recursive: true);
    }
    return _dir!;
  }

  static Future<Directory> thumbsDirectory() async {
    if (_thumbDir != null) return _thumbDir!;
    final root = await attachmentsDirectory();
    _thumbDir = Directory(p.join(root.path, 'thumbs'));
    if (!_thumbDir!.existsSync()) {
      _thumbDir!.createSync(recursive: true);
    }
    return _thumbDir!;
  }

  static Future<File> fileFor(String filename) async {
    final dir = await attachmentsDirectory();
    return File(p.join(dir.path, filename));
  }

  static Future<File> thumbFileFor(String filename) async {
    final dir = await thumbsDirectory();
    return File(p.join(dir.path, filename));
  }

  /// 压缩后保存原图并生成缩略图，返回文件名。
  static Future<String?> saveJpeg(Uint8List bytes) async {
    final compressed = await compressJpegBytes(bytes, maxSide: 1600, quality: 75);
    final name = '${const Uuid().v4()}.jpg';
    final f = await fileFor(name);
    try {
      await f.writeAsBytes(compressed, flush: true);
      await _writeThumb(name, compressed);
      return name;
    } catch (_) {
      return null;
    }
  }

  /// 写入已下载的原图（同步拉下）并尽量补缩略图。
  static Future<void> saveDownloadedJpeg(String filename, Uint8List bytes) async {
    final f = await fileFor(filename);
    await f.writeAsBytes(bytes, flush: true);
    await ensureThumb(filename);
  }

  static Future<void> _writeThumb(String filename, Uint8List sourceBytes) async {
    try {
      final thumbBytes =
          await compressJpegBytes(sourceBytes, maxSide: 240, quality: 60);
      final tf = await thumbFileFor(filename);
      await tf.writeAsBytes(thumbBytes, flush: true);
    } catch (_) {}
  }

  /// 若缩略图缺失则从原图生成。
  static Future<File?> ensureThumb(String filename) async {
    final tf = await thumbFileFor(filename);
    if (tf.existsSync()) return tf;
    final full = await fileFor(filename);
    if (!full.existsSync()) return null;
    try {
      final bytes = await full.readAsBytes();
      await _writeThumb(filename, bytes);
      if (tf.existsSync()) return tf;
    } catch (_) {}
    return full.existsSync() ? full : null;
  }

  static Future<Uint8List> compressJpegBytes(
    Uint8List bytes, {
    required int maxSide,
    required int quality,
  }) async {
    try {
      final out = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxSide,
        minHeight: maxSide,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (out.isNotEmpty) return Uint8List.fromList(out);
    } catch (_) {}
    return bytes;
  }

  static Future<void> deleteFile(String filename) async {
    final f = await fileFor(filename);
    if (f.existsSync()) {
      await f.delete();
    }
    final t = await thumbFileFor(filename);
    if (t.existsSync()) {
      await t.delete();
    }
  }

  /// 删除目录中未被 [referenced] 引用的 jpg（不含 thumbs 子目录扫描进引用）。
  static Future<int> deleteOrphans(Set<String> referenced) async {
    final dir = await attachmentsDirectory();
    var n = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.toLowerCase().endsWith('.jpg')) continue;
      if (referenced.contains(name)) continue;
      try {
        await entity.delete();
        final t = await thumbFileFor(name);
        if (t.existsSync()) await t.delete();
        n++;
      } catch (_) {}
    }
    return n;
  }
}
