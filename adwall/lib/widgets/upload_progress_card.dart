import 'dart:io';

import 'package:flutter/material.dart';

/// Shows the thumbnail of the file currently being uploaded alongside a
/// linear progress bar tracking upload completion, so the admin gets visual
/// feedback while an ad is being uploaded.
class UploadProgressCard extends StatelessWidget {
  const UploadProgressCard({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.progress,
  });

  final String filePath;
  final String fileName;
  final double progress;

  bool get _isImage {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: _isImage
                  ? Image.file(
                      File(filePath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.image_outlined),
                    )
                  : const ColoredBox(
                      color: Colors.black12,
                      child: Icon(Icons.movie_outlined),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    // The card is removed as soon as the upload call
                    // actually resolves, so once this reaches 1.0 it just
                    // stays pinned full rather than switching to an
                    // indeterminate "still working" animation.
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(progress * 100).clamp(0, 100).floor()}%',
          ),
        ],
      ),
    );
  }
}
