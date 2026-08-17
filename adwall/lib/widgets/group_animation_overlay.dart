import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The `group_animation` SSE payload the backend sends to every TV in a
/// group at (roughly) the same moment - see playGroupAnimation() in
/// next/lib/store.js. Each TV only knows its own [index] and the [total]
/// TV count; combined with the shared [startAt] timestamp that's enough
/// for every screen to independently compute where the snake should be
/// *right now*, without any further coordination.
class GroupAnimationCue {
  const GroupAnimationCue({
    required this.groupId,
    required this.index,
    required this.total,
    required this.startAt,
    required this.durationPerScreenMs,
    required this.color,
  });

  factory GroupAnimationCue.fromJson(Map<String, dynamic> json) => GroupAnimationCue(
        groupId: json['groupId'] as String? ?? '',
        index: (json['index'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 1,
        startAt: (json['startAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        durationPerScreenMs: (json['durationPerScreenMs'] as num?)?.toInt() ?? 1500,
        color: json['color'] as String? ?? '#22C55E',
      );

  final String groupId;
  final int index;
  final int total;
  final int startAt; // epoch ms, shared across every TV in the group.
  final int durationPerScreenMs;
  final String color;
}

/// Renders a snake/comet that sweeps left-to-right across this TV, timed
/// so it appears to continue seamlessly from the previous TV in the group
/// and hand off to the next one, purely from a shared start timestamp:
///
///   globalProgress = (now - startAt) / (total * durationPerScreenMs)
///   localProgress  = globalProgress * total - index      // clamped 0..1
///
/// This screen is only "lit" while localProgress is within [0, 1]; every
/// other TV in the group is computing the same formula with its own
/// index at the same moment, so the lit segment moves from TV 0 to TV
/// (total - 1) in order, without any screen waiting on a signal from its
/// neighbour.
class GroupAnimationOverlay extends StatefulWidget {
  const GroupAnimationOverlay({super.key, required this.cue, required this.onDone});

  final GroupAnimationCue cue;
  final VoidCallback onDone;

  @override
  State<GroupAnimationOverlay> createState() => _GroupAnimationOverlayState();
}

class _GroupAnimationOverlayState extends State<GroupAnimationOverlay>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _localProgress = 0; // 0..1 while this screen is "lit", else outside range.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration _) {
    final cue = widget.cue;
    final totalMs = cue.durationPerScreenMs * cue.total;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - cue.startAt;
    final globalProgress = totalMs <= 0 ? 0.0 : elapsedMs / totalMs;
    final local = globalProgress * cue.total - cue.index;

    if (elapsedMs < 0) {
      // Hasn't started yet (still catching up to the shared startAt).
      if (_localProgress != -1) setState(() => _localProgress = -1);
      return;
    }
    if (globalProgress >= 1) {
      if (!_finished) {
        _finished = true;
        _ticker?.stop();
        widget.onDone();
      }
      return;
    }
    setState(() => _localProgress = local.clamp(-1.0, 2.0));
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  Color get _color {
    final hex = widget.cue.color.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16) ?? 0x22C55E;
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    // Only paint while the snake is actually within (or just entering/
    // leaving) this screen - otherwise stay fully transparent so the ad
    // underneath keeps showing.
    if (_localProgress < -0.05 || _localProgress > 1.05) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _SnakePainter(progress: _localProgress.clamp(0.0, 1.0), color: _color),
        ),
      ),
    );
  }
}

class _SnakePainter extends CustomPainter {
  _SnakePainter({required this.progress, required this.color});

  final double progress; // 0 (left edge) -> 1 (right edge)
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final headX = progress * size.width;
    final headY = size.height / 2 + math.sin(progress * math.pi * 2) * (size.height * 0.12);

    // Fading trail behind the head, so the motion reads as a continuous
    // streak rather than a single dot.
    const trailLength = 0.16; // fraction of screen width
    final trailPixels = size.width * trailLength;
    final trailPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.9)],
      ).createShader(Rect.fromLTWH(headX - trailPixels, 0, trailPixels, size.height))
      ..strokeWidth = size.height * 0.05
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = headX - trailPixels * (1 - t);
      if (x < 0) continue;
      final y = size.height / 2 +
          math.sin((progress - trailLength * (1 - t)) * math.pi * 2) * (size.height * 0.12);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, trailPaint);

    final headPaint = Paint()
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(Offset(headX, headY), size.height * 0.035, headPaint);
    canvas.drawCircle(
      Offset(headX, headY),
      size.height * 0.02,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SnakePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
