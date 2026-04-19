import 'package:flutter/material.dart';
import 'package:neosapien_assignment/features/transfer/presentation/constants/incoming_ui_constants.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/transfer_surface_card.dart';

class IncomingTopStatusCard extends StatelessWidget {
  const IncomingTopStatusCard({
    super.key,
    required this.lastSyncAt,
    required this.syncError,
    required this.totalTransfers,
  });

  /// Last successful list refresh (Realtime snapshot). Null before first payload.
  final DateTime? lastSyncAt;
  final String syncError;
  final int totalTransfers;

  ({IconData iconData, Color iconColor, String headline}) _bannerStyle() {
    if (syncError.isNotEmpty) {
      return (
        iconData: Icons.cloud_off_rounded,
        iconColor: Colors.orange.shade700,
        headline: 'Couldn’t refresh',
      );
    }
    if (lastSyncAt == null) {
      return (
        iconData: Icons.hourglass_empty_rounded,
        iconColor: Colors.blueGrey.shade600,
        headline: 'Connecting',
      );
    }
    return (
      iconData: Icons.cloud_done_rounded,
      iconColor: Colors.green.shade700,
      headline: 'Connected',
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _bannerStyle();

    return TransferSurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(style.iconData, size: 24, color: style.iconColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.headline.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'INCOMING TRANSFERS',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$totalTransfers',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IncomingInfoBanner extends StatelessWidget {
  const IncomingInfoBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TransferSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_rounded, size: 22, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class IncomingErrorBanner extends StatelessWidget {
  const IncomingErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 22, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.error,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ActionRequiredHeaderDelegate extends SliverPersistentHeaderDelegate {
  ActionRequiredHeaderDelegate({
    required this.color,
    required this.textColor,
    required this.count,
    this.onTap,
  });

  final Color color;
  final Color textColor;
  final int count;
  final VoidCallback? onTap;

  @override
  double get minExtent => IncomingUiConstants.statusHeaderHeight;

  @override
  double get maxExtent => IncomingUiConstants.statusHeaderHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: maxExtent,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: IncomingUiConstants.pagePadding,
          vertical: 4,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(IncomingUiConstants.cardRadius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(IncomingUiConstants.cardRadius),
                boxShadow: overlapsContent
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.notification_important_outlined,
                      size: 18,
                      color: textColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Action required: $count incoming request(s) waiting',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant ActionRequiredHeaderDelegate oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.textColor != textColor ||
        oldDelegate.count != count;
  }
}
