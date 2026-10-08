import 'package:flutter/material.dart';

import '../circle/photo_repository.dart';
import '../theme/readuo_theme.dart';

class CirclePhoto extends StatefulWidget {
  const CirclePhoto({
    required this.storagePath,
    required this.repository,
    this.aspectRatio = 4 / 3,
    super.key,
  });

  final String storagePath;
  final CirclePhotoRepository repository;
  final double aspectRatio;

  @override
  State<CirclePhoto> createState() => _CirclePhotoState();
}

class _CirclePhotoState extends State<CirclePhoto> {
  late var _photo = widget.repository.load(widget.storagePath);

  @override
  void didUpdateWidget(covariant CirclePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath ||
        oldWidget.repository != widget.repository) {
      _photo = widget.repository.load(widget.storagePath);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ColoredBox(
        color: ReaduoColors.accentTint,
        child: FutureBuilder(
          key: ValueKey(_photo),
          future: _photo,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (snapshot.hasError ||
                (snapshot.connectionState == ConnectionState.done &&
                    bytes == null)) {
              return const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: ReaduoColors.muted,
                ),
              );
            }
            if (bytes == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Image.memory(bytes, fit: BoxFit.cover);
          },
        ),
      ),
    ),
  );
}
