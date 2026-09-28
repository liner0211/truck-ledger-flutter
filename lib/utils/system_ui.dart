import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 真正贴边全屏：内容画到屏幕物理边缘，系统栏透明叠在上面。
void enableEdgeToEdgeUi({Brightness? statusBarIconBrightness}) {
  if (kIsWeb) return;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  applySystemUiOverlay(statusBarIconBrightness: statusBarIconBrightness);
}

void applySystemUiOverlay({Brightness? statusBarIconBrightness}) {
  final iconBright = statusBarIconBrightness ?? Brightness.light;
  final opposite =
      iconBright == Brightness.dark ? Brightness.light : Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBright,
      statusBarBrightness: opposite, // iOS
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBright,
      systemNavigationBarContrastEnforced: false,
    ),
  );
}
