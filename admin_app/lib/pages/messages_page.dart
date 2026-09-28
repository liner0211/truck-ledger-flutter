import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../admin_session.dart';
import '../ui/admin_widgets.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    this.initialTab,
    this.openMessageId,
    this.openThreadId,
  });

  /// 0 发送 / 1 站内信管理 / 2 客服
  final int? initialTab;
  final int? openMessageId;
  final int? openThreadId;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialTab ?? 0).clamp(0, 3);
    _tabs = TabController(length: 4, vsync: this, initialIndex: initial);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleDeepOpen());
  }

  Future<void> _handleDeepOpen() async {
    final mid = widget.openMessageId;
    final tid = widget.openThreadId;
    if (mid != null && mid > 0) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _InboxDetailSheet(
          messageId: mid,
          onChanged: () async {},
        ),
      );
    } else if (tid != null && tid > 0) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _SupportDetailSheet(
          threadId: tid,
          onChanged: () async {},
        ),
      );
    }
    if (mounted) {
      context.read<AdminSession>().clearPendingNav();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: PageHeader(
            title: '消息',
            subtitle: '站内通知 · 客服 · 用户聊天监管',
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: '发送'),
            Tab(text: '站内信'),
            Tab(text: '客服'),
            Tab(text: '用户聊天'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _ComposeTab(),
              _InboxManageTab(),
              _SupportTab(),
              _UserChatAdminTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ComposeTab extends StatefulWidget {
  const _ComposeTab();

  @override
  State<_ComposeTab> createState() => _ComposeTabState();
}

class _ComposeTabState extends State<_ComposeTab> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  int? _selectedUserId;
  bool _loadingUsers = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final list = await context.read<AdminSession>().api.users();
      if (mounted) {
        setState(() {
          _users = list;
          _loadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写标题和内容')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<AdminSession>().api.push(
            title: title,
            body: body,
            userId: _selectedUserId ?? 0,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已发送')));
      _title.clear();
      _body.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        AdminSection(
          title: '撰写并发送站内通知',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loadingUsers)
                const LinearProgressIndicator()
              else
                DropdownButtonFormField<int?>(
                  initialValue: _selectedUserId,
                  decoration: const InputDecoration(labelText: '收件人'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('全体广播'),
                    ),
                    for (final u in _users)
                      DropdownMenuItem<int?>(
                        value: (u['id'] as num).toInt(),
                        child: Text('${u['username']}（#${u['id']}）'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedUserId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                decoration: const InputDecoration(labelText: '内容'),
                maxLines: 5,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InboxManageTab extends StatefulWidget {
  const _InboxManageTab();

  @override
  State<_InboxManageTab> createState() => _InboxManageTabState();
}

class _InboxManageTabState extends State<_InboxManageTab> {
  bool _loading = true;
  bool _refreshing = false;
  List<Map<String, dynamic>> _items = [];
  String? _error;
  StreamSubscription? _rtSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AdminSession>().realtimeEvents.listen((e) {
      if (e['type'] == 'inbox' && mounted) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 280), () {
          if (mounted) _load(silent: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent || _items.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await context.read<AdminSession>().api.inboxMessages();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
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

  Future<void> _openDetail(Map<String, dynamic> row) async {
    final id = (row['id'] as num).toInt();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _InboxDetailSheet(messageId: id, onChanged: () => _load()),
    );
  }

  Future<void> _forceDelete(Map<String, dynamic> row) async {
    final id = (row['id'] as num).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('强制删除'),
        content: Text('确定删除「${row['title']}」？用户端将立即不可见，且不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('强制删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AdminSession>().api.forceDeleteInboxMessage(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已强制删除')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: () => _load(), child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无站内信'),
            TextButton(onPressed: () => _load(), child: const Text('刷新')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final m = _items[i];
          final read = (m['read_count'] as num?)?.toInt() ?? 0;
          final audience = (m['audience'] as num?)?.toInt() ?? 0;
          final replies = (m['reply_count'] as num?)?.toInt() ?? 0;
          final created = (m['created_at'] as num?)?.toInt() ?? 0;
          final target = m['is_broadcast'] == true
              ? '全体'
              : (m['target_username']?.toString() ?? '用户');
          return ListTile(
            title: Text('${m['title']}'),
            subtitle: Text(
              '$target · 已读 $read/$audience · 回复 $replies\n'
              '${created > 0 ? fmt.format(DateTime.fromMillisecondsSinceEpoch(created)) : ''}',
            ),
            isThreeLine: true,
            onTap: () => _openDetail(m),
            trailing: IconButton(
              tooltip: '强制删除',
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: () => _forceDelete(m),
            ),
          );
        },
      ),
    );
  }
}

class _InboxDetailSheet extends StatefulWidget {
  const _InboxDetailSheet({required this.messageId, required this.onChanged});

  final int messageId;
  final Future<void> Function() onChanged;

  @override
  State<_InboxDetailSheet> createState() => _InboxDetailSheetState();
}

class _InboxDetailSheetState extends State<_InboxDetailSheet> {
  final _reply = TextEditingController();
  bool _loading = true;
  bool _refreshing = false;
  Map<String, dynamic>? _data;
  StreamSubscription? _rtSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AdminSession>().realtimeEvents.listen((e) {
      if (e['type'] != 'inbox' || !mounted) return;
      final mid = (e['message_id'] as num?)?.toInt();
      if (mid != null && mid != widget.messageId) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 280), () {
        if (mounted) _load(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rtSub?.cancel();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent || _data == null) setState(() => _loading = true);
    try {
      final d = await context.read<AdminSession>().api.inboxMessageDetail(widget.messageId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    try {
      await context.read<AdminSession>().api.replyInboxMessage(widget.messageId, text);
      _reply.clear();
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final msg = (_data?['message'] as Map?)?.cast<String, dynamic>();
    final replies = (_data?['replies'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final reads = (_data?['reads'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Text(msg?['title']?.toString() ?? '', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(msg?['body']?.toString() ?? ''),
            const SizedBox(height: 16),
            Text('已读回执（${reads.length}）', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (reads.isEmpty)
              const Text('暂无人已读')
            else
              for (final r in reads)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${r['username']}'),
                  subtitle: Text(
                    fmt.format(
                      DateTime.fromMillisecondsSinceEpoch(
                        (r['read_at'] as num?)?.toInt() ?? 0,
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 12),
            Text('回复（${replies.length}）', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final r in replies)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r['sender_role'] == 'admin' ? Icons.support_agent : Icons.person,
                ),
                title: Text('${r['body']}'),
                subtitle: Text(
                  '${r['sender_role'] == 'admin' ? '管理员' : '用户'} · '
                  '${fmt.format(DateTime.fromMillisecondsSinceEpoch((r['created_at'] as num?)?.toInt() ?? 0))}',
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _reply,
              decoration: const InputDecoration(
                labelText: '回复用户',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _sendReply, child: const Text('发送回复')),
          ],
        );
      },
    );
  }
}

class _SupportTab extends StatefulWidget {
  const _SupportTab();

  @override
  State<_SupportTab> createState() => _SupportTabState();
}

class _SupportTabState extends State<_SupportTab> {
  bool _loading = true;
  bool _refreshing = false;
  List<Map<String, dynamic>> _threads = [];
  StreamSubscription? _rtSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AdminSession>().realtimeEvents.listen((e) {
      if (e['type'] == 'support' && mounted) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 280), () {
          if (mounted) _load(silent: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent || _threads.isEmpty) setState(() => _loading = true);
    try {
      final list = await context.read<AdminSession>().api.supportThreads();
      if (!mounted) return;
      setState(() {
        _threads = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _open(Map<String, dynamic> t) async {
    final id = (t['id'] as num).toInt();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SupportDetailSheet(threadId: id, onChanged: () => _load()),
    );
    await _load(silent: true);
  }

  Future<void> _deleteThread(Map<String, dynamic> t) async {
    final id = (t['id'] as num).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('强制删除与 ${t['username']} 的全部客服消息？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AdminSession>().api.deleteSupportThread(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无用户发起的客服会话'),
            TextButton(onPressed: () => _load(), child: const Text('刷新')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _threads.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final t = _threads[i];
          final unread = (t['unread_for_admin'] as num?)?.toInt() ?? 0;
          return ListTile(
            leading: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.forum_outlined),
            ),
            title: Text('${t['username']}（#${t['user_id']}）'),
            subtitle: Text(unread > 0 ? '$unread 条未读' : '无未读'),
            onTap: () => _open(t),
            trailing: IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: () => _deleteThread(t),
            ),
          );
        },
      ),
    );
  }
}

class _SupportDetailSheet extends StatefulWidget {
  const _SupportDetailSheet({required this.threadId, required this.onChanged});

  final int threadId;
  final Future<void> Function() onChanged;

  @override
  State<_SupportDetailSheet> createState() => _SupportDetailSheetState();
}

class _SupportDetailSheetState extends State<_SupportDetailSheet> {
  final _input = TextEditingController();
  bool _loading = true;
  bool _refreshing = false;
  List<Map<String, dynamic>> _messages = [];
  String _username = '';
  StreamSubscription? _rtSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AdminSession>().realtimeEvents.listen((e) {
      if (e['type'] != 'support' || !mounted) return;
      final tid = (e['thread_id'] as num?)?.toInt();
      if (tid != null && tid != widget.threadId && e['event'] != 'deleted') return;
      if (e['event'] == 'deleted' && tid == widget.threadId) {
        Navigator.pop(context);
        return;
      }
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 280), () {
        if (mounted) _load(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rtSub?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent || _messages.isEmpty) setState(() => _loading = true);
    try {
      final d = await context.read<AdminSession>().api.supportThreadDetail(widget.threadId);
      if (!mounted) return;
      final thread = (d['thread'] as Map?)?.cast<String, dynamic>() ?? {};
      final msgs = (d['messages'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      setState(() {
        _username = thread['username']?.toString() ?? '';
        _messages = msgs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    try {
      await context.read<AdminSession>().api.replySupportThread(widget.threadId, text);
      _input.clear();
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deleteMsg(int id) async {
    await context.read<AdminSession>().api.deleteSupportMessage(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (ctx, scroll) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('与 $_username 的会话', style: Theme.of(context).textTheme.titleLarge),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _messages.length,
                      itemBuilder: (c, i) {
                        final m = _messages[i];
                        final admin = m['sender_role'] == 'admin';
                        return ListTile(
                          title: Text('${m['body']}'),
                          subtitle: Text(
                            '${admin ? '管理员' : '用户'} · '
                            '${fmt.format(DateTime.fromMillisecondsSinceEpoch((m['created_at'] as num?)?.toInt() ?? 0))}'
                            '${m['read_by_peer_at'] != null ? ' · 对方已读' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteMsg((m['id'] as num).toInt()),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(
                        hintText: '回复用户…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _send, child: const Text('发送')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 用户私聊/群聊监管（只读消息 + 删消息 / 解散会话）。
class _UserChatAdminTab extends StatefulWidget {
  const _UserChatAdminTab();

  @override
  State<_UserChatAdminTab> createState() => _UserChatAdminTabState();
}

class _UserChatAdminTabState extends State<_UserChatAdminTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  StreamSubscription? _rtSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _rtSub = context.read<AdminSession>().realtimeEvents.listen((e) {
      if (e['type'] == 'chat' && mounted) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 320), () {
          if (mounted) _load(silent: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await context.read<AdminSession>().api.chatConversations();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _open(Map<String, dynamic> c) async {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ChatAdminDetailSheet(
        conversationId: id,
        onChanged: () => _load(silent: true),
      ),
    );
    if (mounted) await _load(silent: true);
  }

  String _titleOf(Map<String, dynamic> c) {
    final t = '${c['title'] ?? ''}'.trim();
    if (t.isNotEmpty) return t;
    final type = '${c['type'] ?? 'dm'}';
    return type == 'group' ? '群聊 #${c['id']}' : '私聊 #${c['id']}';
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无用户聊天会话'));
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final c = _items[i];
          final last = c['last_message'];
          final preview = last is Map ? '${last['body'] ?? ''}' : '';
          final updated = (c['updated_at'] as num?)?.toInt() ?? 0;
          final type = '${c['type'] ?? 'dm'}';
          return ListTile(
            leading: Icon(type == 'group' ? Icons.groups_outlined : Icons.person_outline),
            title: Text(_titleOf(c)),
            subtitle: Text(
              [
                type == 'group' ? '群聊' : '私聊',
                if (preview.isNotEmpty) preview,
                if (updated > 0) fmt.format(DateTime.fromMillisecondsSinceEpoch(updated)),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _open(c),
          );
        },
      ),
    );
  }
}

class _ChatAdminDetailSheet extends StatefulWidget {
  const _ChatAdminDetailSheet({
    required this.conversationId,
    required this.onChanged,
  });

  final int conversationId;
  final Future<void> Function() onChanged;

  @override
  State<_ChatAdminDetailSheet> createState() => _ChatAdminDetailSheetState();
}

class _ChatAdminDetailSheetState extends State<_ChatAdminDetailSheet> {
  bool _loading = true;
  String _title = '';
  String _type = 'dm';
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = await context
          .read<AdminSession>()
          .api
          .chatConversationDetail(widget.conversationId);
      final conv = (m['conversation'] as Map?)?.cast<String, dynamic>() ?? {};
      final msgs = (m['messages'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _type = '${conv['type'] ?? 'dm'}';
        final t = '${conv['title'] ?? ''}'.trim();
        _title = t.isNotEmpty
            ? t
            : (_type == 'group'
                ? '群聊 #${widget.conversationId}'
                : '私聊 #${widget.conversationId}');
        _messages = msgs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteMsg(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('强制删除该条用户聊天消息？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AdminSession>().api.deleteChatMessage(id);
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _dissolve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散会话'),
        content: const Text('解散后成员将无法继续该会话，确认？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('解散')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context
          .read<AdminSession>()
          .api
          .dissolveChatConversation(widget.conversationId);
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM-dd HH:mm');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (ctx, scroll) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _dissolve,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('解散'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _messages.length,
                      itemBuilder: (c, i) {
                        final m = _messages[i];
                        final who = '${m['sender_username'] ?? m['sender_user_id'] ?? ''}';
                        return ListTile(
                          title: Text('${m['body']}'),
                          subtitle: Text(
                            '$who · '
                            '${fmt.format(DateTime.fromMillisecondsSinceEpoch((m['created_at'] as num?)?.toInt() ?? 0))}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                _deleteMsg((m['id'] as num).toInt()),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
