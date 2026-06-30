import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 本应用运行时权限说明与申请。
///
/// **Android / iOS 联网**：访问公网（如 https://truck.liner0211.online）不需要、也无法
/// 弹出「网络权限」对话框。Android 的 [PermissionGroup.network] 中 INTERNET 等为
/// 普通权限，安装时自动授予（见 Android 官方文档 Normal permissions）。
///
/// **需要用户点「允许」的权限**：相册（添加凭证照片）。在首次启动时自动弹出系统授权框。
class AppPermissionService {
  AppPermissionService._();

  /// 安装即授予、无运行时弹窗（Android 普通权限 / iOS 无对应项）。
  static const installTimeGrants = <String>[
    'INTERNET（访问互联网）',
    'ACCESS_NETWORK_STATE（检测网络状态）',
  ];

  /// 启动时尝试申请的危险权限。
  static Future<AppPermissionReport> requestAllRuntimePermissions() async {
    final report = AppPermissionReport();

    if (Platform.isIOS) {
      report.photos = await _requestIosPhotos();
    } else if (Platform.isAndroid) {
      report.photos = await _requestAndroidPhotos();
    } else {
      report.photos = PermissionStatus.granted;
    }

    return report;
  }

  static Future<PermissionStatus> _requestIosPhotos() async {
    var status = await Permission.photos.status;
    if (status.isGranted || status.isLimited) return status;
    return Permission.photos.request();
  }

  static Future<PermissionStatus> _requestAndroidPhotos() async {
    // Android 13+ (API 33)：READ_MEDIA_IMAGES → Permission.photos
    var status = await Permission.photos.status;
    if (!status.isGranted && !status.isLimited) {
      status = await Permission.photos.request();
    }
    if (status.isGranted || status.isLimited) return status;

    // Android 12 及以下：READ_EXTERNAL_STORAGE
    status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status;
  }

  static String photosStatusLabel(PermissionStatus status) {
    if (status.isGranted) return '已允许（全部）';
    if (status.isLimited) return '已允许（部分照片）';
    if (status.isDenied) return '未允许';
    if (status.isPermanentlyDenied) return '已拒绝，需在系统设置中开启';
    return status.name;
  }
}

class AppPermissionReport {
  PermissionStatus photos = PermissionStatus.denied;

  bool get photosOk =>
      photos.isGranted || photos.isLimited;

  bool get photosNeedsSettings => photos.isPermanentlyDenied;
}
