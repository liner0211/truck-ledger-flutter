import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_permission_service.dart';
import 'attachment_store.dart';

/// 选图前确保相册权限，返回保存后的附件文件名列表。
Future<List<String>> pickAndSaveAttachmentPhotos(BuildContext context) async {
  final report = await AppPermissionService.requestAllRuntimePermissions();
  if (!report.photosOk) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要相册权限才能添加照片')),
      );
      if (report.photosNeedsSettings) {
        await openAppSettings();
      }
    }
    return [];
  }

  final files = await ImagePicker().pickMultiImage(imageQuality: 85);
  final names = <String>[];
  for (final x in files) {
    final bytes = await x.readAsBytes();
    final name = await AttachmentStore.saveJpeg(bytes);
    if (name != null) names.add(name);
  }
  return names;
}
