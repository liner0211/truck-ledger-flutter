import 'package:flutter/material.dart';

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
