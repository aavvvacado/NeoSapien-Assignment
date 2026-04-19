import 'package:flutter/material.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer_file.dart';

class IncomingUiHelpers {
  const IncomingUiHelpers._();

  static IconData iconForFileName(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) {
      return Icons.image_outlined;
    }
    if (['mp4', 'mov', 'mkv', 'avi', 'webm'].contains(ext)) {
      return Icons.movie_outlined;
    }
    if (['mp3', 'wav', 'm4a', 'aac', 'flac'].contains(ext)) {
      return Icons.audiotrack_outlined;
    }
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'].contains(ext)) {
      return Icons.description_outlined;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  static IconData primaryTransferIcon(List<TransferFile> files) {
    if (files.isEmpty) return Icons.file_copy_outlined;
    return iconForFileName(files.first.name);
  }

  /// Second line under the file name on Receive (avoids "100%" before anything is saved locally).
  static String incomingFileStatusLine(Transfer transfer, TransferFile file) {
    final size = formatBytes(file.size);
    if (transfer.status == TransferStatus.completed && file.status == TransferFileStatus.completed) {
      return '$size · Saved to device';
    }
    if (transfer.status == TransferStatus.downloading) {
      if (file.status == TransferFileStatus.completed) {
        return '$size · Saved';
      }
      if (file.status == TransferFileStatus.downloading) {
        return '$size · ${(file.progress * 100).toStringAsFixed(0)}%';
      }
    }
    if (file.status == TransferFileStatus.completed &&
        transfer.status != TransferStatus.completed &&
        transfer.status != TransferStatus.downloading) {
      return '$size · On server — tap Receive to save';
    }
    if (file.status == TransferFileStatus.uploading) {
      return '$size · Sender uploading ${(file.progress * 100).toStringAsFixed(0)}%';
    }
    return '$size · ${(file.progress * 100).toStringAsFixed(0)}%';
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Progress for **Receive** UI: sender upload bytes on the row must not read as "saved here".
  /// Uses [Transfer.progress] only when it reflects receiver download or completed state.
  static double receiverAggregateProgress(Transfer transfer) {
    switch (transfer.status) {
      case TransferStatus.completed:
        return 1.0;
      case TransferStatus.downloading:
        return transfer.totalBytes > 0 ? transfer.progress.clamp(0.0, 1.0) : 0.0;
      case TransferStatus.uploading:
      case TransferStatus.initiated:
        return transfer.totalBytes > 0 ? transfer.progress.clamp(0.0, 1.0) : 0.0;
      case TransferStatus.uploaded:
      case TransferStatus.notifying:
      case TransferStatus.failed:
      case TransferStatus.cancelled:
      case TransferStatus.expired:
        return 0.0;
    }
  }

  static String formatEta(Transfer transfer, double progress) {
    if (progress <= 0 || progress >= 1) return '--';
    final elapsed = DateTime.now().difference(transfer.createdAt);
    if (elapsed.inSeconds <= 0) return '--';
    final totalEstimatedSeconds = elapsed.inSeconds / progress;
    final remainingSeconds = (totalEstimatedSeconds - elapsed.inSeconds).round();
    if (remainingSeconds <= 0) return '0s';
    if (remainingSeconds < 60) return '${remainingSeconds}s';
    final mins = remainingSeconds ~/ 60;
    final secs = remainingSeconds % 60;
    return '${mins}m ${secs}s';
  }

  /// Banners that should stay **info** (not red error styling).
  static bool isTransientInfoMessage(String message) {
    if (message.isEmpty) return true;
    if (message == 'Downloading...') return true;
    if (message.startsWith('Transfer declined')) return true;
    return false;
  }

  /// Hide misleading aggregate 0% for states where nothing is being pulled yet.
  static bool showReceiverAggregatePercent(TransferStatus status) {
    return status == TransferStatus.initiated ||
        status == TransferStatus.uploading ||
        status == TransferStatus.downloading;
  }

  static bool canReceive(TransferStatus status) {
    return status == TransferStatus.initiated ||
        status == TransferStatus.uploading ||
        status == TransferStatus.uploaded ||
        status == TransferStatus.notifying ||
        status == TransferStatus.failed;
  }

  static String statusLabel(TransferStatus status) {
    switch (status) {
      case TransferStatus.initiated:
        return 'Incoming request';
      case TransferStatus.uploading:
        return 'Receiving (Sender uploading)';
      case TransferStatus.uploaded:
      case TransferStatus.notifying:
        return 'Ready to receive';
      case TransferStatus.downloading:
        return 'Downloading';
      case TransferStatus.completed:
        return 'Completed';
      case TransferStatus.failed:
        return 'Failed';
      case TransferStatus.cancelled:
        return 'Declined';
      case TransferStatus.expired:
        return 'Expired';
    }
  }

  static Color statusColor(BuildContext context, TransferStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case TransferStatus.completed:
        return Colors.green.shade700;
      case TransferStatus.failed:
      case TransferStatus.expired:
        return scheme.error;
      case TransferStatus.downloading:
      case TransferStatus.uploading:
      case TransferStatus.notifying:
        return scheme.primary;
      case TransferStatus.cancelled:
        return scheme.outline;
      case TransferStatus.initiated:
      case TransferStatus.uploaded:
        return scheme.secondary;
    }
  }

  static List<Transfer> sortByPriority(List<Transfer> input) {
    int priority(TransferStatus status) {
      switch (status) {
        case TransferStatus.initiated:
        case TransferStatus.uploading:
        case TransferStatus.uploaded:
        case TransferStatus.notifying:
          return 0;
        case TransferStatus.downloading:
          return 1;
        case TransferStatus.failed:
          return 2;
        case TransferStatus.completed:
          return 3;
        case TransferStatus.cancelled:
        case TransferStatus.expired:
          return 4;
      }
    }

    final sorted = [...input];
    sorted.sort((a, b) {
      final p = priority(a.status).compareTo(priority(b.status));
      if (p != 0) return p;
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }
}
