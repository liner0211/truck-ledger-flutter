import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:truck_ledger_editor/truck_ledger_editor.dart';

import '../services/auth_api.dart';
import '../services/messages_api.dart';
import '../state/auth_controller.dart';
import '../state/ledger_controller.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _loading = true;
  String? _error;
  List<InboxMessage> _messages = [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().messagesApi;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.list();
      if (!mounted) return;
      setState(() {
        _messages = r.messages;
        _unread = r.unread;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _markAll() async {
    final api = context.read<AuthController>().messagesApi;
    if (api == null) return;
    await api.markAllRead();
    await _load();
    if (mounted) {
      await context.read<AuthController>().refreshInbox();
    }
  }

  Future<File?> _cacheMessageImage(InboxMessage m, String filename) async {
    final api = context.read<AuthController>().messagesApi;
    if (api == null) return null;
    final dir = await getTemporaryDirectory();
    final dest = File(p.join(dir.path, 'msg_${m.id}_$filename'));
    if (dest.existsSync() && dest.lengthSync() > 0) return dest;
    try {
      final bytes = await api.downloadAttachment(m.id, filename);
      await dest.writeAsBytes(bytes, flush: true);
      return dest;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openMessage(InboxMessage m) async {
    final api = context.read<AuthController>().messagesApi;
    if (api != null && !m.isRead) {
      await api.markRead(m.id);
      await context.read<AuthController>().refreshInbox();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) {
        final tripTitle = m.meta?.tripTitle ?? '';
        final tripId = m.meta?.tripId ?? '';
        final images = m.meta?.images ?? const <String>[];
        return AlertDialog(
          title: Text(m.title),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tripTitle.isNotEmpty || tripId.isNotEmpty)
                    Material(
                      color: Theme.of(c).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: tripId.isEmpty
                            ? null
                            : () {
                                Navigator.pop(c);
                                _openTrip(tripId);
                              },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              const Icon(Icons.link, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tripTitle.isNotEmpty ? '引用圈次：$tripTitle' : '引用圈次',
                                  style: Theme.of(c).textTheme.bodyMedium,
                                ),
                              ),
                              if (tripId.isNotEmpty)
                                Icon(Icons.chevron_right, color: Theme.of(c).colorScheme.outline),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (tripTitle.isNotEmpty) const SizedBox(height: 12),
                  Text(m.body),
                  if (images.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in images)
                          FutureBuilder<File?>(
                            future: _cacheMessageImage(m, name),
                            builder: (ctx, snap) {
                              final f = snap.data;
                              if (f == null) {
                                return const SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              }
                              final dpr = MediaQuery.devicePixelRatioOf(ctx);
                              final cacheW = math.min(256, (72 * dpr).round());
                              return InkWell(
                                onTap: () {
                                  Navigator.push<void>(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => ImageViewerPage(path: f.path),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    f,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    cacheWidth: cacheW,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
          ],
        );
      },
    );
    await _load();
  }

  void _openTrip(String tripId) {
    final ctrl = context.read<LedgerController>();
    TripLedger? found;
    for (final r in ctrl.book.rounds) {
      if (r.id == tripId) {
        found = r;
        break;
      }
    }
    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地未找到该圈次，请先同步账本')),
      );
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TripDetailScreen(
          initial: found!.copy(),
          money: ctrl.money,
          allRounds: ctrl.book.rounds,
          onReplace: (updated) => ctrl.replaceTrip(updated),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: Text(_unread > 0 ? '消息（$_unread）' : '消息'),
        actions: [
          if (_unread > 0)
            TextButton(onPressed: _markAll, child: const Text('全部已读')),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _messages.isEmpty
                  ? const Center(child: Text('暂无消息'))
                  : ListView.separated(
                      itemCount: _messages.length,
                      separatorBuilder: (_, i) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final m = _messages[i];
                        final time = m.createdAt > 0
                            ? fmt.format(
                                DateTime.fromMillisecondsSinceEpoch(m.createdAt),
                              )
                            : '';
                        final ref = m.meta?.tripTitle;
                        final isReconcile = m.type == 'ops.reconcile';
                        return ListTile(
                          leading: Icon(
                            m.isRead
                                ? Icons.mark_email_read_outlined
                                : (isReconcile
                                    ? Icons.fact_check_outlined
                                    : Icons.mark_email_unread),
                            color: m.isRead
                                ? null
                                : Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            m.title,
                            style: TextStyle(
                              fontWeight: m.isRead ? FontWeight.normal : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (ref != null && ref.isNotEmpty) '引用：$ref',
                              m.body,
                              time,
                            ].where((e) => e.isNotEmpty).join('\n'),
                          ),
                          isThreeLine: true,
                          onTap: () => _openMessage(m),
                        );
                      },
                    ),
    );
  }
}
