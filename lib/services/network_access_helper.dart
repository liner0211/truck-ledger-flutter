import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Android 联网权限说明与检测（INTERNET 为安装时自动授予，无系统弹窗）。
class NetworkAccessHelper {
  NetworkAccessHelper._();

  static Future<String?> checkBeforeRequest() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    final results = await Connectivity().checkConnectivity();
    final offline = results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
    if (offline) {
      return '当前无网络连接，请打开 WLAN 或移动数据';
    }
    return null;
  }

  static String friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('ERR_NAME_NOT_RESOLVED') ||
        text.contains('Failed host lookup') ||
        text.contains('No address associated with hostname')) {
      return '无法解析服务器域名（不是权限未授予）。\n'
          '请确认服务器地址正确，或点击下方「应用联网设置」检查是否禁止本应用联网。';
    }
    if (text.contains('Redirect loop') || text.contains('Redirect limit')) {
      return '服务器返回了异常重定向，请检查域名与 HTTPS 配置。';
    }
    if (text.contains('connection abort') ||
        text.contains('Software caused connection abort')) {
      return '与服务器的连接被中断。\n'
          '请确认 WLAN/移动数据正常，或稍后重试。';
    }
    if (text.contains('SocketException') ||
        text.contains('Network is unreachable') ||
        text.contains('Connection refused')) {
      return '网络连接失败。\n'
          '请到 设置 → 应用 → 卡车记账，确认已允许 WLAN 与移动数据。';
    }
    return '无法连接服务器：$error';
  }

  static Future<void> openAppNetworkSettings() => ph.openAppSettings();
}
