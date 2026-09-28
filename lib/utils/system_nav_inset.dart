import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android 系统导航与底部 inset（需先 enableEdgeToEdgeUi）。
///
/// Material3 [NavigationBar] 内部自带 [SafeArea]，若再手动
/// `Padding(bottom: viewPadding)` 会叠成约两倍高度。请用 [wrap]。
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

  /// 仅三键/两键时返回系统导航栏高度；手势 / iOS 为 0。
  static double bottomForNavBar(BuildContext context) {
    if (kIsWeb) return 0;
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

  /// 包住 [NavigationBar]：去掉其内置 SafeArea 底垫，再按虚拟键高度抬一次。
  static Widget wrap(BuildContext context, {required Widget child}) {
    final inset = bottomForNavBar(context);
    return MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: child,
      ),
    );
  }
}
