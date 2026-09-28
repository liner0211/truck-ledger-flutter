import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android 系统导航模式与底部 inset。
/// - 三键/两键虚拟导航：按系统报告高度抬起底栏
/// - 手势导航：返回 0，底栏贴边，保持全屏
class SystemNavInset {
  SystemNavInset._();

  static const _channel = MethodChannel('com.liner0211.truckledger/system_nav');

  /// 0=三键, 1=两键, 2=手势；非 Android 为 null
  static int? _mode;

  static Future<void> ensureLoaded() async {
    if (_mode != null) return;
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final raw = await _channel.invokeMethod<dynamic>('getBottomNavInfo');
      if (raw is Map) {
        final m = raw['mode'];
        if (m is int) {
          _mode = m;
        } else if (m is num) {
          _mode = m.toInt();
        }
      }
    } catch (_) {
      // 引擎未就绪时稍后由 Shell 重试；期间走启发式
    }
  }

  /// 底栏（如 NavigationBar）下方应预留的高度。
  /// 手势导航为 0；虚拟按键为 [MediaQuery.viewPadding.bottom]（随旋转实时变化）。
  static double bottomForNavBar(BuildContext context) {
    final viewBottom = MediaQuery.viewPaddingOf(context).bottom;
    if (viewBottom <= 0) return 0;

    if (kIsWeb) return 0;

    if (Platform.isIOS) {
      // Home Indicator：避开即可，高度取系统 inset
      return viewBottom;
    }

    if (!Platform.isAndroid) return 0;

    final mode = _mode;
    if (mode == 2) {
      // 手势导航：不额外垫高，贴边全屏
      return 0;
    }
    if (mode == 0 || mode == 1) {
      // 虚拟按键：用系统实时报告的导航栏高度
      return viewBottom;
    }

    // 通道未就绪时的启发式：细指示条通常 < 36，三键栏常见 ≥ 48
    final gesture = MediaQuery.systemGestureInsetsOf(context);
    final looksLikeGesture =
        gesture.left > 0 || gesture.right > 0 || viewBottom < 36;
    if (looksLikeGesture) return 0;
    return viewBottom;
  }
}
