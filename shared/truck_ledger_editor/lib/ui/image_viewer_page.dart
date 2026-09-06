import 'dart:io';

import 'package:flutter/material.dart';

class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('图片'),
      ),
      body: Center(
        child: file.existsSync()
            ? InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.file(file, fit: BoxFit.contain),
              )
            : const Text('无法加载图片', style: TextStyle(color: Colors.white70)),
      ),
    );
  }
}
