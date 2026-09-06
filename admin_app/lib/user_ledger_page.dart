import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ledger_excel.dart';
import 'main.dart';

class UserLedgerPage extends StatefulWidget {
  const UserLedgerPage({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<UserLedgerPage> createState() => _UserLedgerPageState();
}

class _UserLedgerPageState extends State<UserLedgerPage> {
  Map<String, dynamic>? _ledger;
  String? _err;
  bool _busy = false;
  bool _openingWeb = false;
  final _jsonEdit = TextEditingController();
  bool _editMode = false;
  bool _autoOpened = false;

  int get _userId => (widget.user['id'] as num).toInt();
  String get _username => '${widget.user['username'] ?? ''}';
  String get _ledgerRedirect => '/admin/users/$_userId/ledger';

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_autoOpened && mounted) {
        _autoOpened = true;
        _openFullEditor(silentFail: true);
      }
    });
  }

  @override
  void dispose() {
    _jsonEdit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final ledger = await context.read<AdminSession>().api.userLedger(_userId);
      if (!mounted) return;
      setState(() {
        _ledger = ledger;
        _jsonEdit.text = const JsonEncoder.withIndent('  ').convert(ledger);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _openFullEditor({bool silentFail = false}) async {
    if (_openingWeb) return;
    setState(() => _openingWeb = true);
    try {
      final uri = await context.read<AdminSession>().api.createWebTicketUri(_ledgerRedirect);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('无法打开系统浏览器');
      if (!mounted) return;
      if (!silentFail) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已打开完整账本编辑器（与网页后台相同）')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (!silentFail) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打开失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _openingWeb = false);
    }
  }

  Future<void> _save() async {
    final canWrite = context.read<AdminSession>().admin?.can('ledger.write') == true;
    if (!canWrite) return;
    setState(() => _busy = true);
    try {
      final decoded = jsonDecode(_jsonEdit.text);
      if (decoded is! Map) throw StateError('账本须为 JSON 对象');
      final saved = await context.read<AdminSession>().api.putUserLedger(
            _userId,
            Map<String, dynamic>.from(decoded),
          );
      if (!mounted) return;
      setState(() {
        _ledger = saved;
        _jsonEdit.text = const JsonEncoder.withIndent('  ').convert(saved);
        _editMode = false;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('账本已保存')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _exportExcel() async {
    final ledger = _ledger;
    if (ledger == null) return;
    try {
      final bytes = AdminLedgerExcel.buildBytes(ledger, title: _username);
      final name = 'ledger_${_username}_$_userId.xlsx';
      await Share.shareXFiles([
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: name,
        ),
      ], subject: '账本导出 $_username');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  bool _truthy(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = '$v'.toLowerCase();
    return s == 'true' || s == '1';
  }

  Future<void> _toggleSettled(int index) async {
    final ledger = _ledger;
    if (ledger == null) return;
    final rounds = List<dynamic>.from((ledger['rounds'] as List?) ?? const []);
    if (index < 0 || index >= rounds.length) return;
    final r = Map<String, dynamic>.from((rounds[index] as Map).cast<String, dynamic>());
    final cur = _truthy(r['settled'] ?? r['accountSettled'] ?? r['account_settled']);
    r['settled'] = !cur;
    r['accountSettled'] = !cur;
    rounds[index] = r;
    final next = Map<String, dynamic>.from(ledger);
    next['rounds'] = rounds;
    setState(() => _busy = true);
    try {
      final saved = await context.read<AdminSession>().api.putUserLedger(_userId, next);
      if (!mounted) return;
      setState(() {
        _ledger = saved;
        _jsonEdit.text = const JsonEncoder.withIndent('  ').convert(saved);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSession>().admin;
    final canWrite = admin?.can('ledger.write') == true;
    final rounds = (_ledger?['rounds'] as List?) ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('账本 · $_username'),
        actions: [
          IconButton(
            tooltip: '打开完整编辑器',
            onPressed: _openingWeb ? null : () => _openFullEditor(),
            icon: _openingWeb
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_browser),
          ),
          IconButton(
            tooltip: '导出 Excel',
            onPressed: _ledger == null || _busy ? null : _exportExcel,
            icon: const Icon(Icons.table_view_outlined),
          ),
          if (canWrite)
            IconButton(
              tooltip: _editMode ? '取消编辑' : '高级编辑 JSON',
              onPressed: _busy ? null : () => setState(() => _editMode = !_editMode),
              icon: Icon(_editMode ? Icons.close : Icons.data_object),
            ),
          IconButton(
            tooltip: '刷新摘要',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy && _ledger == null
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!))
              : _editMode
                  ? Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: TextField(
                              controller: _jsonEdit,
                              maxLines: null,
                              expands: true,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: '账本 JSON（高级）',
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.save),
                            label: const Text('保存到云端'),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Card(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '完整账本编辑（与网页后台相同）',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '会计对账、改错、附件与圈次明细请在网页编辑器中操作。'
                                  '进入本页会自动打开；也可再次点击下方按钮。',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _openingWeb ? null : () => _openFullEditor(),
                                  icon: const Icon(Icons.edit_note),
                                  label: Text(_openingWeb ? '正在打开…' : '打开完整账本编辑器'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'revision ${_ledger?['revision'] ?? '—'} · 更新 ${_ledger?['updated_at'] ?? '—'}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text('摘要 · 共 ${rounds.length} 个圈次', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: _ledger == null ? null : _exportExcel,
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('导出 Excel'),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(rounds.length, (i) {
                          final r = (rounds[i] as Map).cast<String, dynamic>();
                          final start = '${r['startPlace'] ?? r['start_place'] ?? ''}';
                          final end = '${r['endPlace'] ?? r['end_place'] ?? ''}';
                          final expenses = (r['expenses'] as List?) ?? const [];
                          double exp = 0;
                          for (final e in expenses) {
                            if (e is Map) {
                              final a = e['amount'];
                              exp += a is num ? a.toDouble() : double.tryParse('$a') ?? 0;
                            }
                          }
                          return Card(
                            child: ListTile(
                              title: Text('${i + 1}. $start → $end'),
                              subtitle: Text(
                                '费用合计 ¥${exp.toStringAsFixed(2)} · '
                                '交账 ${(_truthy(r['settled'] ?? r['accountSettled'])) ? '是' : '否'} · '
                                '工资 ${(_truthy(r['wageSettled'] ?? r['wage_settled'])) ? '是' : '否'}',
                              ),
                              trailing: canWrite
                                  ? IconButton(
                                      tooltip: '切换交账标记',
                                      icon: const Icon(Icons.fact_check_outlined),
                                      onPressed: () => _toggleSettled(i),
                                    )
                                  : null,
                            ),
                          );
                        }),
                      ],
                    ),
    );
  }
}
