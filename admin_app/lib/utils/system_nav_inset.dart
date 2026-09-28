import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 见司机端同名工具：去掉 NavigationBar 内置 SafeArea 底垫，避免双倍高度。
class SystemNavInset {
  SystemNavInset._();

  static const _channel = MethodChannel('com.liner0211.truckledger/system_nav');

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

  static Widget wrap(BuildContext context, {required Widget child}) {
    final inset = bottomForNavBar(context);
    return MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          if (inset > 0) SizedBox(height: inset),
        ],
      ),
    );
  }
}
