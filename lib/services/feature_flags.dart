import 'dart:convert';

/// 远端功能开关（来自 /api/auth/config 或 app/check）。
class FeatureFlags {
  FeatureFlags({
    this.excelExport = true,
    this.backupImport = true,
    this.messages = true,
    this.webLedger = true,
    this.raw = const {},
  });

  final bool excelExport;
  final bool backupImport;
  final bool messages;
  final bool webLedger;
  final Map<String, dynamic> raw;

  bool enabled(String key, {bool defaultValue = true}) {
    if (raw.containsKey(key)) {
      final v = raw[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
    }
    switch (key) {
      case 'excel_export':
        return excelExport;
      case 'backup_import':
        return backupImport;
      case 'messages':
        return messages;
      case 'web_ledger':
        return webLedger;
      default:
        return defaultValue;
    }
  }

  factory FeatureFlags.fromJson(Map<String, dynamic>? m) {
    final map = m ?? {};
    bool flag(String k, bool d) {
      final v = map[k];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return d;
    }

    return FeatureFlags(
      excelExport: flag('excel_export', true),
      backupImport: flag('backup_import', true),
      messages: flag('messages', true),
      webLedger: flag('web_ledger', true),
      raw: Map<String, dynamic>.from(map),
    );
  }

  static FeatureFlags tryParse(dynamic raw) {
    if (raw is Map<String, dynamic>) return FeatureFlags.fromJson(raw);
    if (raw is Map) return FeatureFlags.fromJson(raw.cast<String, dynamic>());
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return FeatureFlags.fromJson(d.cast<String, dynamic>());
      } catch (_) {}
    }
    return FeatureFlags();
  }
}
