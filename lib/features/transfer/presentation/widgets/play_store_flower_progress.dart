import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Play Store–inspired rotating segmented ring (flower / spiral feel).
class PlayStoreFlowerProgress extends StatefulWidget {
  const PlayStoreFlowerProgress({
    super.key,
    this.value,
    required this.active,
    this.size = 32,
    this.strokeWidth = 3.2,
    this.color,
  });

  /// 0..1 determinate; when null and [active], runs indeterminate rotation.
  final double? value;
  final bool active;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  State<PlayStoreFlowerProgress> createState() => _PlayStoreFlowerProgressState();
}

class _PlayStoreFlowerProgressState extends State<PlayStoreFlowerProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.active && widget.value == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant PlayStoreFlowerProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    final indeterminate = widget.active && widget.value == null;
    final wasIndeterminate = oldWidget.active && oldWidget.value == null;
    if (indeterminate && !wasIndeterminate) {
      _controller.repeat();
    } else if (!indeterminate && wasIndeterminate) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final rotation = widget.value == null ? _controller.value * 2 * math.pi : 0.0;
          return CustomPaint(
            painter: _FlowerRingPainter(
              rotation: rotation,
              progress: widget.value,
              color: color,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class _FlowerRingPainter extends CustomPainter {
  _FlowerRingPainter({
    required this.rotation,
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double rotation;
  final double? progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - strokeWidth;
    final rect = Rect.fromCircle(center: c, radius: radius);

    if (progress != null) {
      final p = progress!.clamp(0.0, 1.0);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(c, radius, paint);

      final fg = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      const start = -math.pi / 2;
      canvas.drawArc(rect, start, 2 * math.pi * p, false, fg);
      return;
    }

    const petals = 6;
    final sweep = (2 * math.pi / petals) * 0.55;
    for (var i = 0; i < petals; i++) {
      final t = i / petals;
      final paint = Paint()
        ..color = Color.lerp(
          color.withValues(alpha: 0.95),
          color.withValues(alpha: 0.35),
          t,
        )!
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final start = rotation + i * (2 * math.pi / petals);
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowerRingPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
