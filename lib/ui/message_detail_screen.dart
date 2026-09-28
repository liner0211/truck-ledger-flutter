import 'dart:async';
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

class MessageDetailScreen extends StatefulWidget {
  const MessageDetailScreen({super.key, required this.messageId});

  final int messageId;

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  final _replyCtrl = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  bool _refreshing = false;
  String? _error;
  InboxMessage? _msg;
  StreamSubscription? _rtSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AuthController>().realtimeEvents.listen((e) {
      if (e['type'] != 'inbox' || !mounted) return;
      final mid = (e['message_id'] as num?)?.toInt();
      final event = e['event']?.toString();
      if (event == 'deleted' && mid == widget.messageId) {
        Navigator.pop(context);
        return;
      }
      // 本条回复/已读变更，或广播类事件（无 message_id）
      if (mid == widget.messageId || (mid == null && event != 'deleted')) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 280), () {
          if (mounted && !_sending) _load(silent: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rtSub?.cancel();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final api = context.read<AuthController>().messagesApi;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }
    if (_refreshing) return;
    _refreshing = true;
    if (!silent || _msg == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (!silent) await api.markRead(widget.messageId);
      final detail = await api.detail(widget.messageId);
      if (!mounted) return;
      setState(() {
        _msg = detail;
        _loading = false;
        _error = null;
      });
      await context.read<AuthController>().refreshInbox();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = '$e';
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final api = context.read<AuthController>().messagesApi;
    if (api == null) return;
    setState(() => _sending = true);
    try {
      await api.reply(widget.messageId, text);
      if (!mounted) return;
      _replyCtrl.clear();
      setState(() => _sending = false);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<File?> _cacheImage(String filename) async {
    final api = context.read<AuthController>().messagesApi;
    final m = _msg;
    if (api == null || m == null) return null;
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
    final cs = Theme.of(context).colorScheme;
    final m = _msg;
    return Scaffold(
      appBar: AppBar(title: Text(m?.title ?? '消息详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : m == null
                  ? const Center(child: Text('消息不存在'))
                  : Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    m.isRead
                                        ? Icons.mark_email_read_outlined
                                        : Icons.mark_email_unread,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    m.isRead ? '已读' : '未读',
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                  const Spacer(),
                                  Text(
                                    m.createdAt > 0
                                        ? fmt.format(
                                            DateTime.fromMillisecondsSinceEpoch(
                                              m.createdAt,
                                            ),
                                          )
                                        : '',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(m.body, style: Theme.of(context).textTheme.bodyLarge),
                              if ((m.meta?.tripId ?? '').isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.link),
                                  title: Text(
                                    m.meta!.tripTitle.isNotEmpty
                                        ? '引用圈次：${m.meta!.tripTitle}'
                                        : '引用圈次',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openTrip(m.meta!.tripId),
                                ),
                              ],
                              if ((m.meta?.images ?? []).isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final name in m.meta!.images)
                                      FutureBuilder<File?>(
                                        future: _cacheImage(name),
                                        builder: (ctx, snap) {
                                          final f = snap.data;
                                          if (f == null) {
                                            return const SizedBox(
                                              width: 72,
                                              height: 72,
                                              child: Center(
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              ),
                                            );
                                          }
                                          final dpr = MediaQuery.devicePixelRatioOf(ctx);
                                          return ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.file(
                                              f,
                                              width: 72,
                                              height: 72,
                                              fit: BoxFit.cover,
                                              cacheWidth: math.min(256, (72 * dpr).round()),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 20),
                              Text(
                                '回复（${m.replies.length}）',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              if (m.replies.isEmpty)
                                Text(
                                  '暂无回复，可在下方留言给管理员',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                )
                              else
                                for (final r in m.replies)
                                  Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: Icon(
                                        r.isAdmin
                                            ? Icons.support_agent
                                            : Icons.person_outline,
                                      ),
                                      title: Text(r.body),
                                      subtitle: Text(
                                        '${r.isAdmin ? '管理员' : '我'} · '
                                        '${fmt.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt))}',
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _replyCtrl,
                                    minLines: 1,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      hintText: '回复这条站内信…',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _sending ? null : _sendReply,
                                  child: const Text('回复'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
