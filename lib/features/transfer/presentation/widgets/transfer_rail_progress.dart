import 'package:flutter/material.dart';

/// Rounded full-width progress bar (Play Store–style rail).
class TransferRailProgress extends StatelessWidget {
  const TransferRailProgress({
    super.key,
    this.value,
    this.semanticsLabel,
    this.color,
    this.backgroundColor,
  });

  /// Null means indeterminate shimmer rail.
  final double? value;
  final String? semanticsLabel;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: value,
          minHeight: 6,
          backgroundColor: backgroundColor ?? scheme.surfaceContainerHighest,
          color: color ?? scheme.primary,
          borderRadius: BorderRadius.circular(8),
          semanticsLabel: semanticsLabel,
        ),
      ),
    );
  }
}
