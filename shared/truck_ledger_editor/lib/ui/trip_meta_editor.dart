import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

typedef TripMetaResult = ({String start, String end});

/// 与 `TripMetaEditorViewController` 一致：开始/结束时间（`yyyy-MM-dd HH:mm`）。
class TripMetaEditorPage extends StatefulWidget {
  const TripMetaEditorPage({super.key, required this.start, required this.end});

  final String start;
  final String end;

  @override
  State<TripMetaEditorPage> createState() => _TripMetaEditorPageState();
}

class _TripMetaEditorPageState extends State<TripMetaEditorPage> {
  static final _fmt = DateFormat('yyyy-MM-dd HH:mm');
  late String _start;
  late String _end;

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    _end = widget.end;
  }

  Future<void> _pickStart() async {
    final initial = _tryParse(_start) ?? DateTime.now();
    final picked = await _pickDateTime(context, initial);
    if (picked != null) setState(() => _start = _fmt.format(picked));
  }

  Future<void> _pickEnd() async {
    final initial = _tryParse(_end) ?? DateTime.now();
    final picked = await _pickDateTime(context, initial);
    if (picked != null) setState(() => _end = _fmt.format(picked));
  }

  DateTime? _tryParse(String s) {
    try {
      return _fmt.parse(s.trim());
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
    const zh = Locale('zh', 'CN');
    final d = await showDatePicker(
      context: context,
      locale: zh,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!context.mounted || d == null) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) {
        return Localizations.override(
          context: ctx,
          locale: zh,
          child: MediaQuery(
            data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
    if (!context.mounted || t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('圈次信息'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop<TripMetaResult>(context, (start: _start, end: _end)),
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('开始时间'),
            subtitle: Text(_start.isEmpty ? '点此选择' : _start),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickStart,
          ),
          ListTile(
            title: const Text('结束时间'),
            subtitle: Text(_end.isEmpty ? '点此选择' : _end),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickEnd,
          ),
        ],
      ),
    );
  }
}
