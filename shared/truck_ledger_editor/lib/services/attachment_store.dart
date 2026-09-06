import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 与 Swift `AttachmentStore` 一致：`Documents/attachments/` 下存 JPEG，文件名为 UUID。
/// 管理端可通过 [userScope] 隔离不同用户的本地缓存目录。
class AttachmentStore {
  AttachmentStore._();

  static Directory? _dir;
  static String? _userScope;

  /// 例如 `admin_12`；设为 null 时使用默认 `attachments/`（主 App）。
  static String? get userScope => _userScope;

  static set userScope(String? value) {
    final next = (value == null || value.isEmpty) ? null : value;
    if (_userScope == next) return;
    _userScope = next;
    _dir = null;
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

  static Future<File> fileFor(String filename) async {
    final dir = await attachmentsDirectory();
    return File(p.join(dir.path, filename));
  }

  static Future<String?> saveJpeg(Uint8List bytes) async {
    final name = '${const Uuid().v4()}.jpg';
    final f = await fileFor(name);
    try {
      await f.writeAsBytes(bytes, flush: true);
      return name;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteFile(String filename) async {
    final f = await fileFor(filename);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}
