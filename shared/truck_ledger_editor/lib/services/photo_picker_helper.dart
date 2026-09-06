import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'attachment_store.dart';

/// 选图并保存为附件文件名列表（权限由宿主 App 在启动时申请）。
Future<List<String>> pickAndSaveAttachmentPhotos(BuildContext context) async {
  final files = await ImagePicker().pickMultiImage(imageQuality: 85);
  final names = <String>[];
  for (final x in files) {
    final bytes = await x.readAsBytes();
    final name = await AttachmentStore.saveJpeg(bytes);
    if (name != null) names.add(name);
  }
  return names;
}
