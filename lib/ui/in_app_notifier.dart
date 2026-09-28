import 'dart:async';

import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../services/notif_sound.dart';

/// 软件内顶部消息通知（可点击跳转）。
class InAppNotifier {
  InAppNotifier._();
  static final InAppNotifier instance = InAppNotifier._();

  OverlayEntry? _entry;
  Timer? _hide;

  void show({
    required String title,
    String? body,
    VoidCallback? onTap,
    bool playSound = true,
    Duration duration = const Duration(seconds: 5),
  }) {
    if (playSound) {
      unawaited(NotifSound.play());
    }
    final overlay = AppNav.navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _hide?.cancel();
    _entry?.remove();
    _entry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final top = MediaQuery.of(ctx).padding.top + 8;
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              bottom: false,
              child: _BannerCard(
                title: title,
                body: body,
                onTap: () {
                  dismiss();
                  onTap?.call();
                },
                onClose: dismiss,
              ),
            ),
          ),
        );
      },
    );
    _entry = entry;
    overlay.insert(entry);
    _hide = Timer(duration, dismiss);
  }

  void dismiss() {
    _hide?.cancel();
    _hide = null;
    _entry?.remove();
    _entry = null;
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.title,
    this.body,
    this.onTap,
    this.onClose,
  });

  final String title;
  final String? body;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: const ValueKey('in_app_banner'),
      direction: DismissDirection.up,
      onDismissed: (_) => onClose?.call(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.notifications_active, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (body != null && body!.trim().isNotEmpty)
                      Text(
                        body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Text(
                      '点击查看',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
