import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The `group_animation` SSE payload the backend broadcasts to every TV in
/// a group at once - see playGroupAnimation() in next/lib/store.js. Each TV
/// only knows its own [index] and the [total] TV count; combined with the
/// shared [startAt] timestamp that's enough for every screen to seek to
/// (roughly) the same playback position without any further coordination.
class GroupAnimationCue {
  const GroupAnimationCue({
    required this.groupId,
    required this.index,
    required this.total,
    required this.mediaUrl,
    required this.mediaType,
    required this.startAt,
  });

  factory GroupAnimationCue.fromJson(Map<String, dynamic> json) => GroupAnimationCue(
        groupId: json['groupId'] as String? ?? '',
        index: (json['index'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 1,
        mediaUrl: json['mediaUrl'] as String? ?? '',
        mediaType: json['mediaType'] as String? ?? 'video',
        startAt: (json['startAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      );

  final String groupId;
  final int index;
  final int total;
  final String mediaUrl; // relative path as sent by the backend, e.g. '/media/x.mp4'
  final String mediaType; // 'video'
  final int startAt; // epoch ms, shared across every TV in the group.

  bool get hasMedia => mediaUrl.isNotEmpty;
}

/// Plays the group's video stretched across every TV in the group at once:
/// each TV only shows the vertical slice of the frame that corresponds to
/// its [GroupAnimationCue.index] out of [GroupAnimationCue.total], stretched
/// (aspect ratio ignored) to fill its own screen - so lined-up TVs together
/// display one continuous wide video. Loops forever until a new cue arrives.
class GroupAnimationOverlay extends StatefulWidget {
  const GroupAnimationOverlay({
    super.key,
    required this.cue,
    required this.resolvedMediaUrl,
  });

  final GroupAnimationCue cue;

  /// [cue.mediaUrl] turned into a fully-qualified URL the TV can load
  /// from (see PairingService.resolveMediaUrl).
  final String resolvedMediaUrl;

  @override
  State<GroupAnimationOverlay> createState() => _GroupAnimationOverlayState();
}

class _GroupAnimationOverlayState extends State<GroupAnimationOverlay>
    with SingleTickerProviderStateMixin {
  static const _fadeDuration = Duration(milliseconds: 450);

  VideoPlayerController? _controller;
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: _fadeDuration)
      ..forward();
    if (widget.cue.hasMedia) _initVideo();
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.resolvedMediaUrl));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      // Every TV in the group received the same startAt, so seeking each
      // one to (now - startAt) lines them up at (roughly) the same point
      // in the video before playback begins.
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - widget.cue.startAt;
      final videoDurationMs = controller.value.duration.inMilliseconds;
      if (elapsedMs > 0 && videoDurationMs > 0) {
        await controller.seekTo(Duration(milliseconds: elapsedMs % videoDurationMs));
      }
      setState(() => _controller = controller);
      await controller.play();
    } catch (_) {
      // Couldn't load the video - nothing further to do on this TV.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Widget _buildSlice() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final total = widget.cue.total.clamp(1, 1000000);
    final index = widget.cue.index.clamp(0, total - 1);
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;
          return OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(-index * screenWidth, 0),
              child: SizedBox(
                // The full "virtual wall" width across every TV in the
                // group; VideoPlayer stretches to fill whatever box it's
                // given (no aspect-ratio preservation), which is exactly
                // the stretched look this needs.
                width: screenWidth * total,
                height: screenHeight,
                child: VideoPlayer(controller),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: widget.cue.hasMedia ? _buildSlice() : const SizedBox.shrink(),
      ),
    );
  }
}
