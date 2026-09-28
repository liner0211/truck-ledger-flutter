import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotifSound {
  NotifSound._();
  static final AudioPlayer _player = AudioPlayer();
  static bool _ready = false;

  static Future<void> play() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
    try {
      if (!_ready) {
        await _player.setReleaseMode(ReleaseMode.stop);
        _ready = true;
      }
      await _player.stop();
      await _player.play(AssetSource('sounds/notify.wav'), volume: 0.85);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NotifSound] $e');
      }
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }
}
