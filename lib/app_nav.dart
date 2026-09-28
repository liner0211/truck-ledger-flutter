import 'package:flutter/material.dart';

/// 全局导航，供软件内通知点击跳转。
class AppNav {
  AppNav._();
  static final navigatorKey = GlobalKey<NavigatorState>();

  static NavigatorState? get nav => navigatorKey.currentState;

  static Future<T?> push<T>(Route<T> route) {
    final n = nav;
    if (n == null) return Future<T?>.value(null);
    return n.push(route);
  }
}
