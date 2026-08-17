import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The `group_animation` SSE payload the backend sends when the group's
/// turn reaches this TV - see playGroupAnimation()/advanceGroupAnimation()
/// in next/lib/store.js. Each TV only knows its own [index] and the
/// [total] TV count; when this TV finishes playing [mediaUrl] it reports
/// back (see PairingService.reportGroupAnimationFinished) so the backend
/// can send the same cue to tvCodes[index + 1], and so on down the order.
class GroupAnimationCue {
  const GroupAnimationCue({
    required this.groupId,
    required this.index,
    required this.total,
    required this.mediaUrl,
    required this.mediaType,
    required this.durationSeconds,
  });

  factory GroupAnimationCue.fromJson(Map<String, dynamic> json) => GroupAnimationCue(
        groupId: json['groupId'] as String? ?? '',
        index: (json['index'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 1,
        mediaUrl: json['mediaUrl'] as String? ?? '',
        mediaType: json['mediaType'] as String? ?? 'image',
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 8,
      );

  final String groupId;
  final int index;
  final int total;
  final String mediaUrl; // relative path as sent by the backend, e.g. '/media/x.mp4'
  final String mediaType; // 'image' or 'video'
  final int durationSeconds; // only used for images
}

/// Full-screen playback of the group's animation media on this TV. Plays
/// once - an image for [GroupAnimationCue.durationSeconds], or a video to
/// its natural end - then calls [onDone], which the TV screen uses to tell
/// the backend this screen finished, handing playback off to the next TV
/// in the group's order.
class GroupAnimationOverlay extends StatefulWidget {
  const GroupAnimationOverlay({
    super.key,
    required this.cue,
    required this.resolvedMediaUrl,
    required this.onDone,
  });

  final GroupAnimationCue cue;

  /// [cue.mediaUrl] turned into a fully-qualified URL the TV can load
  /// from (see PairingService.resolveMediaUrl).
  final String resolvedMediaUrl;

  final VoidCallback onDone;

  @override
  State<GroupAnimationOverlay> createState() => _GroupAnimationOverlayState();
}

class _GroupAnimationOverlayState extends State<GroupAnimationOverlay> {
  VideoPlayerController? _videoController;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.cue.mediaType == 'video') {
      _initVideo();
    } else {
      Future.delayed(
        Duration(seconds: widget.cue.durationSeconds.clamp(1, 3600)),
        _finish,
      );
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.resolvedMediaUrl));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoTick);
      setState(() => _videoController = controller);
      await controller.play();
    } catch (_) {
      // Couldn't load the video - don't leave this TV stuck waiting
      // forever for a hand-off that will never come.
      _finish();
    }
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    if (!value.isPlaying &&
        value.position >= value.duration &&
        value.duration > Duration.zero) {
      _finish();
    }
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (widget.cue.mediaType == 'video') {
      final controller = _videoController;
      if (controller == null || !controller.value.isInitialized) {
        content = const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      } else {
        content = Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        );
      }
    } else {
      content = Image.network(
        widget.resolvedMediaUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Don't leave this TV stuck if the image fails to load.
          WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
          return const Icon(Icons.broken_image, color: Colors.white54, size: 64);
        },
      );
    }
    return Container(color: Colors.black, alignment: Alignment.center, child: content);
  }
}
