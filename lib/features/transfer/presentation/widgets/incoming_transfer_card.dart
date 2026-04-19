import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neosapien_assignment/core/platform/native_download_saver.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer_file.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/incoming_ui_helpers.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/play_store_flower_progress.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/transfer_rail_progress.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/transfer_surface_card.dart';

/// [TransferFileStatus.completed] is reused for "uploaded to relay" and "saved on device";
/// only non-empty [TransferFile.localSavedPath] means the receiver can open the file.
bool incomingFileHasLocalSavePath(TransferFile file) {
  final p = file.localSavedPath;
  return p != null && p.trim().isNotEmpty;
}

String incomingOpenErrorDetail(Object e) {
  if (e is PlatformException) {
    final m = e.message;
    if (m != null && m.isNotEmpty) {
      return m;
    }
    return e.code;
  }
  return e.toString();
}

class IncomingTransferCard extends StatelessWidget {
  const IncomingTransferCard({
    super.key,
    required this.transfer,
    required this.isExpanded,
    required this.nativeBridge,
    required this.onToggleExpand,
    required this.onReceive,
    this.onDownloadAgain,
  });

  final Transfer transfer;
  final bool isExpanded;
  final NativeDownloadSaver nativeBridge;
  final VoidCallback onToggleExpand;
  final VoidCallback onReceive;
  final VoidCallback? onDownloadAgain;

  bool get _showFlower {
    return transfer.status == TransferStatus.downloading ||
        transfer.status == TransferStatus.uploading;
  }

  @override
  Widget build(BuildContext context) {
    final progress = IncomingUiHelpers.receiverAggregateProgress(transfer);
    final visibleFiles = !isExpanded && transfer.files.length > 1
        ? transfer.files.take(1).toList(growable: false)
        : transfer.files;

    return TransferSurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpand,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Row(
              children: [
                _buildStatusIcon(context),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRANSFER · ${transfer.senderUid.substring(0, 8).toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        IncomingUiHelpers.statusLabel(
                          transfer.status,
                        ).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (transfer.status == TransferStatus.completed) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Saved on device (Gallery / Downloads / NeoSapien)',
                          style: TextStyle(
                            color: Color(0xFF3ECF8E),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (transfer.status == TransferStatus.downloading)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'RECEIVING',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: 1.5,
                      ),
                    ),
                  )
                else if (IncomingUiHelpers.canReceive(transfer.status) ||
                    transfer.status == TransferStatus.failed)
                  Material(
                    color: transfer.status == TransferStatus.failed
                        ? Colors.redAccent
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onReceive,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          transfer.status == TransferStatus.failed
                              ? 'RESUME'
                              : 'RECEIVE',
                          style: TextStyle(
                            color: transfer.status == TransferStatus.failed
                                ? Colors.white
                                : Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (transfer.status == TransferStatus.completed)
                  Material(
                    color: const Color(0xFF3ECF8E),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onToggleExpand, // Or a dedicated open logic
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'OPEN',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 1,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 14,
                              color: Colors.black,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white24,
                    size: 24,
                  ),
              ],
            ),
          ),
          if (_showFlower || transfer.status == TransferStatus.completed) ...[
            const SizedBox(height: 16),
            TransferRailProgress(
              value: transfer.status == TransferStatus.completed
                  ? 1.0
                  : progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white10,
              color: Colors.white,
            ),
          ],
          if (visibleFiles.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...visibleFiles.map(
              (file) => _FileItem(
                file: file,
                nativeBridge: nativeBridge,
                transfer: transfer,
                onRetrySave: transfer.status == TransferStatus.completed
                    ? onDownloadAgain
                    : null,
              ),
            ),
          ],
          if (!isExpanded && transfer.files.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '+ ${transfer.files.length - 1} MORE FILES',
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    if (_showFlower) {
      return PlayStoreFlowerProgress(
        active: true,
        value: IncomingUiHelpers.receiverAggregateProgress(transfer),
        size: 40,
        color: Colors.white,
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: transfer.status == TransferStatus.completed
            ? const Color(0xFF3ECF8E).withValues(alpha: 0.1)
            : Colors.white10,
        shape: BoxShape.circle,
      ),
      child: Icon(
        transfer.status == TransferStatus.completed
            ? Icons.check
            : Icons.file_download_outlined,
        color: transfer.status == TransferStatus.completed
            ? const Color(0xFF3ECF8E)
            : Colors.white54,
        size: 20,
      ),
    );
  }
}

class _FileItem extends StatelessWidget {
  const _FileItem({
    required this.file,
    required this.nativeBridge,
    required this.transfer,
    this.onRetrySave,
  });
  final TransferFile file;
  final NativeDownloadSaver nativeBridge;
  final Transfer transfer;
  final VoidCallback? onRetrySave;

  @override
  Widget build(BuildContext context) {
    final isBusy =
        file.status == TransferFileStatus.downloading ||
        file.status == TransferFileStatus.uploading;

    final showPathMissingHint = file.status == TransferFileStatus.completed &&
        !incomingFileHasLocalSavePath(file);
    final pathMissingMessage = transfer.status == TransferStatus.completed
        ? 'Save path not on record. Tap Receive again, or add column '
            'local_saved_path (see docs/supabase_setup.sql).'
        : 'On server — tap Receive to save';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                color: Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  file.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (incomingFileHasLocalSavePath(file)) ...[
                IconButton(
                  onPressed: () async {
                    final path = file.localSavedPath!.trim();
                    try {
                      await nativeBridge.sharePathOrUri(
                        pathOrUri: path,
                        title: 'Share ${file.name}',
                        fileName: file.name,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not share file: ${file.name}. ${incomingOpenErrorDetail(e)}',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  tooltip: 'Share via...',
                  icon: const Icon(
                    Icons.share_rounded,
                    color: Colors.white70,
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () async {
                    final path = file.localSavedPath!.trim();
                    try {
                      await nativeBridge.openUriForView(
                        pathOrUri: path,
                        fileName: file.name,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not open file: ${file.name}. ${incomingOpenErrorDetail(e)}',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white24,
                    size: 14,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
          if (showPathMissingHint) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pathMissingMessage,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                      height: 1.35,
                    ),
                    softWrap: true,
                  ),
                  if (onRetrySave != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onRetrySave,
                      child: const Text('Save to device again'),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (isBusy) ...[
            const SizedBox(height: 4),
            TransferRailProgress(
              value: file.size > 0 ? file.progress.clamp(0.0, 1.0) : null,
              backgroundColor: Colors.white10,
              color: Colors.white30,
            ),
          ],
        ],
      ),
    );
  }
}
