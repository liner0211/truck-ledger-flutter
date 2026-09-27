import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 编辑页本地草稿（SharedPreferences），不写入账本、不触发云同步。
class EditorDraftStore {
  EditorDraftStore._();

  static const debounceMs = 800;

  static String key({
    required String tripId,
    required String kind,
    String? slot,
  }) {
    return 'draft:$tripId:$kind:${slot ?? 'new'}';
  }

  static Future<void> save(String draftKey, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(draftKey, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> load(String draftKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(draftKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clear(String draftKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(draftKey);
  }
}

/// 供编辑页复用：debounce 写草稿 + 生命周期立即落盘。
mixin EditorDraftMixin<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  Timer? _draftTimer;
  String get draftKey;
  Map<String, dynamic> captureDraft();
  void applyDraft(Map<String, dynamic> data);

  bool _draftBannerVisible = false;
  bool get draftBannerVisible => _draftBannerVisible;

  Future<void> initDraftBanner() async {
    final data = await EditorDraftStore.load(draftKey);
    if (!mounted || data == null) return;
    setState(() => _draftBannerVisible = true);
  }

  void scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: EditorDraftStore.debounceMs),
      () => flushDraft(),
    );
  }

  Future<void> flushDraft() async {
    _draftTimer?.cancel();
    _draftTimer = null;
    await EditorDraftStore.save(draftKey, captureDraft());
  }

  Future<void> clearDraft() async {
    _draftTimer?.cancel();
    _draftTimer = null;
    await EditorDraftStore.clear(draftKey);
    if (mounted) setState(() => _draftBannerVisible = false);
  }

  Future<void> restoreDraft() async {
    final data = await EditorDraftStore.load(draftKey);
    if (!mounted || data == null) return;
    setState(() {
      applyDraft(data);
      _draftBannerVisible = false;
    });
  }

  Future<void> discardDraft() async {
    await clearDraft();
  }

  Widget? buildDraftBanner() {
    if (!_draftBannerVisible) return null;
    return Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '发现未保存草稿',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
            ),
            TextButton(onPressed: restoreDraft, child: const Text('恢复')),
            TextButton(onPressed: discardDraft, child: const Text('丢弃')),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      flushDraft();
    }
  }

  void disposeDraft() {
    _draftTimer?.cancel();
    _draftTimer = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
