import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:truck_ledger_editor/truck_ledger_editor.dart';
import 'package:uuid/uuid.dart';

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
  Map<String, dynamic>? _meta;
  String? _err;
  bool _busy = false;
  bool _saving = false;
  double? _progress;
  String _progressMessage = '';
  TripLedger? _lastEdited;

  int get _userId => (widget.user['id'] as num).toInt();
  String get _username => '${widget.user['username'] ?? ''}';
  bool get _canWrite =>
      context.read<AdminSession>().admin?.can('ledger.write') == true;
  bool get _canMessage =>
      context.read<AdminSession>().admin?.can('messages.send') == true;

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

  void _setProgress(String message, double? value) {
    if (!mounted) return;
    setState(() {
      _progressMessage = message;
      _progress = value;
    });
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
      _progress = 0.05;
      _progressMessage = '拉取账本…';
    });
    try {
      final api = context.read<AdminSession>().api;
      final raw = await api.userLedger(_userId);
      final book = LedgerBook.fromJson(raw);
      if (!mounted) return;
      setState(() {
        _book = book;
        _meta = {
          'revision': raw['revision'],
          'updated_at': raw['updated_at'],
        };
        _busy = false;
        _progress = null;
        _progressMessage = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _busy = false;
        _progress = null;
        _progressMessage = '';
      });
    }
  }

  Future<void> ensureTripAttachments(TripLedger trip) async {
    final names = <String>{
      ...trip.routeLegs.expand((e) => e.attachments),
      ...trip.expenses.expand((e) => e.attachments),
      ...trip.cashAdvances.expand((e) => e.attachments),
    };
    if (names.isEmpty) return;
    final api = context.read<AdminSession>().api;
    final list = names.toList();
    for (var i = 0; i < list.length; i++) {
      final name = list[i];
      final f = await AttachmentStore.fileFor(name);
      if (f.existsSync() && f.lengthSync() > 0) continue;
      _setProgress('下载附件 ${i + 1}/${list.length}', 0.2 + 0.7 * (i + 1) / list.length);
      try {
        final bytes = await api.downloadAttachment(_userId, name);
        await f.writeAsBytes(bytes, flush: true);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _progress = null;
        _progressMessage = '';
      });
    }
  }

  Future<void> _persistBook(LedgerBook book, {TripLedger? edited}) async {
    if (!_canWrite) return;
    setState(() => _saving = true);
    try {
      final api = context.read<AdminSession>().api;
      final names = book.collectAttachmentFilenames().toList();
      for (var i = 0; i < names.length; i++) {
        final name = names[i];
        final f = await AttachmentStore.fileFor(name);
        if (!f.existsSync()) continue;
        _setProgress('上传附件 ${i + 1}/${names.length}', (i + 1) / (names.length + 1));
        try {
          await api.uploadAttachment(_userId, name, await f.readAsBytes());
        } catch (_) {}
      }
      _setProgress('保存账本…', 0.95);
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
        _progress = null;
        _progressMessage = '';
        _lastEdited = edited;
      });
      if (_canMessage && edited != null && mounted) {
        await _promptReconcileNote(edited);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _progress = null;
        _progressMessage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      rethrow;
    }
  }

  Future<void> _promptReconcileNote(TripLedger trip) async {
    final send = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('发送对账说明？'),
        content: Text('已保存圈次「${trip.title}」。是否向司机发送说明（可附图）？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('跳过')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('编写说明')),
        ],
      ),
    );
    if (send == true && mounted) {
      await _composeReconcileNote(trip);
    }
  }

  Future<void> _composeReconcileNote(TripLedger trip) async {
    final titleCtrl = TextEditingController(text: '对账说明 · ${trip.title}');
    final bodyCtrl = TextEditingController();
    final images = <({String filename, List<int> bytes})>[];
    final imageLabels = <String>[];

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return StatefulBuilder(
          builder: (c, setLocal) => AlertDialog(
            title: const Text('对账说明'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('引用：${trip.title}', style: Theme.of(c).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '标题')),
                    TextField(
                      controller: bodyCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: '说明内容'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ...imageLabels.map((e) => Chip(label: Text(e))),
                        TextButton.icon(
                          onPressed: () async {
                            final files = await ImagePicker().pickMultiImage(
                              imageQuality: 85,
                              maxWidth: 1920,
                              maxHeight: 1920,
                            );
                            for (final x in files) {
                              final bytes = await x.readAsBytes();
                              final name = '${const Uuid().v4()}.jpg';
                              images.add((filename: name, bytes: bytes));
                              imageLabels.add(x.name);
                            }
                            setLocal(() {});
                          },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('添加图片'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('发送')),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AdminSession>().api.sendReconcileMessage(
            _userId,
            title: titleCtrl.text.trim(),
            body: bodyCtrl.text.trim(),
            tripId: trip.id,
            tripTitle: trip.title,
            images: images,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('对账说明已发送')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$e')));
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
    await _persistBook(next, edited: updated);
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
    await _persistBook(next, edited: trip);
    if (!mounted) return;
    await _openDetail(trip);
  }

  Future<void> _openDetail(TripLedger round) async {
    await ensureTripAttachments(round);
    if (!mounted) return;
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
    final showBar = _progress != null || _saving;

    return Scaffold(
      appBar: AppBar(
        title: Text('账本 · $_username'),
        actions: [
          if (_canMessage && _lastEdited != null)
            IconButton(
              tooltip: '发送对账说明',
              onPressed: () => _composeReconcileNote(_lastEdited!),
              icon: const Icon(Icons.outgoing_mail),
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
        bottom: showBar
            ? PreferredSize(
                preferredSize: const Size.fromHeight(36),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_progressMessage.isNotEmpty)
                        Text(_progressMessage, style: theme.textTheme.labelSmall),
                      LinearProgressIndicator(value: _progress),
                    ],
                  ),
                ),
              )
            : null,
      ),
      floatingActionButton: _canWrite && !_busy
          ? FloatingActionButton.extended(
              onPressed: _addRound,
              icon: const Icon(Icons.add),
              label: const Text('新建圈次'),
            )
          : null,
      body: _busy && _book == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 220,
                    child: LinearProgressIndicator(value: _progress),
                  ),
                  const SizedBox(height: 12),
                  Text(_progressMessage.isEmpty ? '加载中…' : _progressMessage),
                ],
              ),
            )
          : _err != null
              ? Center(child: Text(_err!))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '与客户端相同编辑 · rev ${_meta?['revision'] ?? '—'} · '
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
                                                      : makeTripTitle(round.startPlace, round.endPlace),
                                                  style: theme.textTheme.titleMedium,
                                                ),
                                              ),
                                              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
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
                                                  style: theme.textTheme.bodyMedium?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
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
                                                avatar: Icon(
                                                  round.isReconciled ? Icons.check_circle : Icons.radio_button_unchecked,
                                                  size: 16,
                                                ),
                                                label: Text(round.isReconciled ? '已交账' : '未交账'),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                              Chip(
                                                label: Text(round.isSalarySettled ? '工资已结' : '工资未结'),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                              if (_canMessage)
                                                ActionChip(
                                                  label: const Text('发说明'),
                                                  onPressed: () => _composeReconcileNote(round),
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
