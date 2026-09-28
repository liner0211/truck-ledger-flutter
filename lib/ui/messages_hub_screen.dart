import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import 'chat_list_screen.dart';
import 'messages_screen.dart';
import 'support_chat_screen.dart';

/// 统一消息入口：通知 / 客服 / 聊天。
class MessagesHubScreen extends StatefulWidget {
  const MessagesHubScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<MessagesHubScreen> createState() => _MessagesHubScreenState();
}

class _MessagesHubScreenState extends State<MessagesHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final inbox = auth.unreadInbox;
    final support = auth.unreadSupport;
    final chat = auth.unreadChat;

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: inbox > 0 ? '通知($inbox)' : '通知'),
            Tab(text: support > 0 ? '客服($support)' : '客服'),
            Tab(text: chat > 0 ? '聊天($chat)' : '聊天'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          MessagesScreen(embedded: true),
          SupportChatScreen(embedded: true),
          ChatListScreen(),
        ],
      ),
    );
  }
}
