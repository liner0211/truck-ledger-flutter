import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/attachment_store.dart';
import '../image_viewer_page.dart';

/// 凭证缩略图网格（不显示文件名）。
class AttachmentThumbStrip extends StatelessWidget {
  const AttachmentThumbStrip({
    super.key,
    required this.names,
    this.onAdd,
    this.onRemove,
    this.maxVisible = 6,
    this.compact = false,
  });

  final List<String> names;
  final VoidCallback? onAdd;
  final Future<void> Function(String name)? onRemove;
  final int maxVisible;
  final bool compact;

  Future<void> _open(BuildContext context, String name) async {
    final f = await AttachmentStore.fileFor(name);
    if (!context.mounted) return;
    if (!f.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片文件不存在')),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => ImageViewerPage(path: f.path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = compact ? 56.0 : 72.0;
    final show = names.take(maxVisible).toList();
    final extra = names.length - show.length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onAdd != null)
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: const Icon(Icons.add_photo_alternate_outlined),
            ),
          ),
        for (final name in show)
          _ThumbTile(
            name: name,
            size: size,
            onTap: () => _open(context, name),
            onRemove: onRemove == null ? null : () => onRemove!(name),
          ),
        if (extra > 0)
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('+$extra', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

class _ThumbTile extends StatefulWidget {
  const _ThumbTile({
    required this.name,
    required this.size,
    required this.onTap,
    this.onRemove,
  });

  final String name;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  State<_ThumbTile> createState() => _ThumbTileState();
}

class _ThumbTileState extends State<_ThumbTile> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ThumbTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) _load();
  }

  Future<void> _load() async {
    final f = await AttachmentStore.ensureThumb(widget.name);
    if (mounted) setState(() => _file = f);
  }

  @override
  Widget build(BuildContext context) {
    final cacheW = (widget.size * MediaQuery.devicePixelRatioOf(context)).round();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: _file == null
                  ? ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Image.file(
                      _file!,
                      fit: BoxFit.cover,
                      cacheWidth: cacheW,
                      errorBuilder: (_, error, stack) => const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
        ),
        if (widget.onRemove != null)
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: Theme.of(context).colorScheme.error,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onRemove,
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: Theme.of(context).colorScheme.onError,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
