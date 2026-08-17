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
    this.text,
    this.textColor = '#FFFFFF',
    this.textSize = 48,
    this.textPosition = 'center',
  });

  factory GroupAnimationCue.fromJson(Map<String, dynamic> json) => GroupAnimationCue(
        groupId: json['groupId'] as String? ?? '',
        index: (json['index'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 1,
        mediaUrl: json['mediaUrl'] as String? ?? '',
        mediaType: json['mediaType'] as String? ?? 'image',
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 8,
        text: json['text'] as String?,
        textColor: json['textColor'] as String? ?? '#FFFFFF',
        textSize: (json['textSize'] as num?)?.toDouble() ?? 48,
        textPosition: json['textPosition'] as String? ?? 'center',
      );

  final String groupId;
  final int index;
  final int total;
  final String mediaUrl; // relative path as sent by the backend, e.g. '/media/x.mp4'
  final String mediaType; // 'image' or 'video'
  final int durationSeconds; // only used for images, and for text-only cues

  // Text overlay that slides across the group's TVs the same way the media
  // does - right to left, one screen at a time, in the group's order.
  final String? text;
  final String textColor; // hex, e.g. '#FFFFFF'
  final double textSize;
  final String textPosition; // 'top' | 'center' | 'bottom'

  bool get hasMedia => mediaUrl.isNotEmpty;
  bool get hasText => text != null && text!.trim().isNotEmpty;

  Color get resolvedTextColor {
    var hex = textColor.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.tryParse(hex, radix: 16) ?? 0xFFFFFFFF);
  }

  Alignment get resolvedTextAlignment => switch (textPosition) {
        'top' => const Alignment(0, -0.75),
        'bottom' => const Alignment(0, 0.75),
        _ => Alignment.center,
      };
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

class _GroupAnimationOverlayState extends State<GroupAnimationOverlay>
    with TickerProviderStateMixin {
  static const _fadeDuration = Duration(milliseconds: 450);

  VideoPlayerController? _videoController;
  bool _done = false;

  late final AnimationController _fadeController;
  AnimationController? _textController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: _fadeDuration)
      ..forward();

    if (widget.cue.hasMedia && widget.cue.mediaType == 'video') {
      _initVideo();
    } else {
      // Image, or a text-only cue with no media: the slot length is known
      // up front, so the text slide controller can start immediately.
      final duration = Duration(seconds: widget.cue.durationSeconds.clamp(1, 3600));
      if (widget.cue.hasText) {
        _textController = AnimationController(vsync: this, duration: duration)
          ..forward();
      }
      if (widget.cue.hasMedia) {
        Future.delayed(duration, _finish);
      } else if (widget.cue.hasText) {
        Future.delayed(duration, _finish);
      } else {
        _finish();
      }
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
      if (widget.cue.hasText) {
        final videoDuration = controller.value.duration;
        _textController = AnimationController(
          vsync: this,
          duration: videoDuration > Duration.zero
              ? videoDuration
              : const Duration(seconds: 8),
        )..forward();
      }
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

  Future<void> _finish() async {
    if (_done || !mounted) return;
    _done = true;
    try {
      await _fadeController.reverse();
    } catch (_) {
      // Widget may have been disposed mid-animation - nothing to do.
    }
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _fadeController.dispose();
    _textController?.dispose();
    super.dispose();
  }

  Widget _buildMedia() {
    if (!widget.cue.hasMedia) return const SizedBox.shrink();
    if (widget.cue.mediaType == 'video') {
      final controller = _videoController;
      if (controller == null || !controller.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }
    return Image.network(
      widget.resolvedMediaUrl,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        // Don't leave this TV stuck if the image fails to load.
        WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
        return const Icon(Icons.broken_image, color: Colors.white54, size: 64);
      },
    );
  }

  // Slides the cue's text in from the right edge, holds it in place, then
  // slides it out to the left - so as each TV in the group's order takes
  // its turn, the text appears to travel screen to screen, right to left.
  Widget _buildTextLayer() {
    final controller = _textController;
    if (controller == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        const inEnd = 0.18;
        const outStart = 0.82;
        double dx;
        if (t <= inEnd) {
          final p = Curves.easeOutCubic.transform((t / inEnd).clamp(0.0, 1.0));
          dx = 1.0 - p;
        } else if (t >= outStart) {
          final p = Curves.easeInCubic
              .transform(((t - outStart) / (1 - outStart)).clamp(0.0, 1.0));
          dx = -p;
        } else {
          dx = 0.0;
        }
        return Align(
          alignment: widget.cue.resolvedTextAlignment,
          child: FractionalTranslation(
            translation: Offset(dx, 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.cue.text!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.cue.resolvedTextColor,
                  fontSize: widget.cue.textSize,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMedia(),
            if (widget.cue.hasText) _buildTextLayer(),
          ],
        ),
      ),
    );
  }
}
