import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:truck_ledger_editor/truck_ledger_editor.dart';
import 'package:uuid/uuid.dart';

import 'admin_api.dart';
import 'ledger_excel.dart';
import 'main.dart';

class UserLedgerPage extends StatefulWidget {
  const UserLedgerPage({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<UserLedgerPage> createState() => _UserLedgerPageState();
}

class _UserLedgerPageState extends State<UserLedgerPage> {
  LedgerBook? _book;
  Map<String, dynamic>? _meta; // revision / updated_at from server
  String? _err;
  bool _busy = false;
  bool _saving = false;

  int get _userId => (widget.user['id'] as num).toInt();
  String get _username => '${widget.user['username'] ?? ''}';
  bool get _canWrite =>
      context.read<AdminSession>().admin?.can('ledger.write') == true;

  String _money(double v) => '¥${v.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    AttachmentStore.userScope = 'admin_$_userId';
    _load();
  }

  @override
  void dispose() {
    AttachmentStore.userScope = null;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final api = context.read<AdminSession>().api;
      final raw = await api.userLedger(_userId);
      final book = LedgerBook.fromJson(raw);
      await _ensureLocalAttachments(api, book);
      if (!mounted) return;
      setState(() {
        _book = book;
        _meta = {
          'revision': raw['revision'],
          'updated_at': raw['updated_at'],
        };
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

  Future<void> _ensureLocalAttachments(AdminApi api, LedgerBook book) async {
    for (final name in book.collectAttachmentFilenames()) {
      final f = await AttachmentStore.fileFor(name);
      if (f.existsSync() && f.lengthSync() > 0) continue;
      try {
        final bytes = await api.downloadAttachment(_userId, name);
        await f.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // 个别缺失不阻断打开；查看时可能显示空白
      }
    }
  }

  Future<void> _persistBook(LedgerBook book) async {
    if (!_canWrite) return;
    setState(() => _saving = true);
    try {
      final api = context.read<AdminSession>().api;
      for (final name in book.collectAttachmentFilenames()) {
        final f = await AttachmentStore.fileFor(name);
        if (!f.existsSync()) continue;
        try {
          await api.uploadAttachment(_userId, name, await f.readAsBytes());
        } catch (_) {
          // 已存在等于成功；失败在 PUT 前尽量上传
        }
      }
      final payload = book.toJson();
      if (_meta?['revision'] != null) {
        payload['revision'] = _meta!['revision'];
      }
      final saved = await api.putUserLedger(_userId, payload);
      final next = LedgerBook.fromJson(saved);
      if (!mounted) return;
      setState(() {
        _book = next;
        _meta = {
          'revision': saved['revision'],
          'updated_at': saved['updated_at'],
        };
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      rethrow;
    }
  }

  Future<void> _replaceTrip(TripLedger updated) async {
    final book = _book;
    if (book == null) return;
    final idx = book.rounds.indexWhere((e) => e.id == updated.id);
    if (idx < 0) return;
    final next = book.copy();
    next.rounds[idx] = updated.copy();
    setState(() => _book = next);
    await _persistBook(next);
  }

  Future<void> _addRound() async {
    if (!_canWrite) return;
    final r = await Navigator.push<TripMetaResult>(
      context,
      MaterialPageRoute(builder: (_) => const TripMetaEditorPage(start: '', end: '')),
    );
    if (r == null || !mounted) return;
    final book = _book ?? LedgerBook.empty();
    final trip = TripLedger.empty(const Uuid().v4());
    trip.startPlace = r.start;
    trip.endPlace = r.end;
    trip.title = makeTripTitle(r.start, r.end);
    final next = book.copy();
    next.rounds.insert(0, trip);
    setState(() => _book = next);
    await _persistBook(next);
    if (!mounted) return;
    await _openDetail(trip);
  }

  Future<void> _openDetail(TripLedger round) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TripDetailScreen(
          initial: round.copy(),
          money: _money,
          onReplace: _canWrite
              ? _replaceTrip
              : (updated) async {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前账号仅可查看，无法保存')),
                  );
                },
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _exportExcel() async {
    final book = _book;
    if (book == null) return;
    try {
      final bytes = AdminLedgerExcel.buildBytes(book.toJson(), title: _username);
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

  String _routePreview(TripLedger round) {
    final parts = round.routeLegs
        .map((e) {
          final a = e.loadPlace.trim();
          final b = e.unloadPlace.trim();
          if (a.isEmpty && b.isEmpty) return null;
          if (a.isEmpty) return b;
          if (b.isEmpty) return a;
          return '$a → $b';
        })
        .whereType<String>()
        .toList();
    if (parts.isEmpty) return '路线：暂无';
    return '路线：${parts.join(' ｜ ')}';
  }

  @override
  Widget build(BuildContext context) {
    final rounds = _book?.rounds ?? const <TripLedger>[];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('账本 · $_username'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: '导出 Excel',
            onPressed: _book == null || _busy ? null : _exportExcel,
            icon: const Icon(Icons.table_view_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canWrite && !_busy
          ? FloatingActionButton.extended(
              onPressed: _addRound,
              icon: const Icon(Icons.add),
              label: const Text('新建圈次'),
            )
          : null,
      body: _busy && _book == null
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '与客户端相同的编辑方式 · '
                        'rev ${_meta?['revision'] ?? '—'} · '
                        '共 ${rounds.length} 个圈次'
                        '${_canWrite ? '' : ' · 只读'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: rounds.isEmpty
                          ? const Center(child: Text('暂无圈次'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                              itemCount: rounds.length,
                              itemBuilder: (ctx, i) {
                                final round = rounds[i];
                                final sum = ProfitCalculator.calculate(round);
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _openDetail(round),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  round.title.isNotEmpty
                                                      ? round.title
                                                      : makeTripTitle(
                                                          round.startPlace,
                                                          round.endPlace,
                                                        ),
                                                  style: theme.textTheme.titleMedium,
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right,
                                                color: theme.colorScheme.outline,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _routePreview(round),
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '司机应发 ${_money(sum.driverWagePayable)}',
                                                  style: theme.textTheme.bodyMedium,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  '老板分成 ${_money(sum.ownerShare)}',
                                                  style: theme.textTheme.bodyMedium,
                                                  textAlign: TextAlign.end,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              Chip(
                                                label: Text(
                                                  round.isReconciled ? '已交账' : '未交账',
                                                ),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                              Chip(
                                                label: Text(
                                                  round.isSalarySettled ? '工资已结' : '工资未结',
                                                ),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
