import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android 系统导航与底部 inset（需先 [enableEdgeToEdgeUi]）。
///
/// - 三键/两键：按系统报告的导航栏高度抬起可点区域，底栏背景仍画满全屏
/// - 手势 / iOS Home Indicator：不额外垫高，贴边全屏
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
    } catch (_) {}
  }

  /// 底栏可点区域下方预留高度（背景仍应铺满到屏幕底边）。
  static double bottomForNavBar(BuildContext context) {
    if (kIsWeb) return 0;
    // iOS / 桌面：贴边全屏，Home Indicator 叠在底栏上
    if (!Platform.isAndroid) return 0;

    final viewBottom = MediaQuery.viewPaddingOf(context).bottom;
    if (viewBottom <= 0) return 0;

    final mode = _mode;
    if (mode == 2) return 0;
    if (mode == 0 || mode == 1) return viewBottom;

    final gesture = MediaQuery.systemGestureInsetsOf(context);
    final looksLikeGesture =
        gesture.left > 0 || gesture.right > 0 || viewBottom < 36;
    if (looksLikeGesture) return 0;
    return viewBottom;
  }
}
