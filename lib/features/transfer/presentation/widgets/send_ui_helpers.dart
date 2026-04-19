import 'package:flutter/material.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer_file.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/send_transfer_bloc.dart';

class SendUiHelpers {
  const SendUiHelpers._();

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

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatEta(SendTransferState state) {
    if (state.transferProgress <= 0 || state.transferProgress >= 1) return '--';
    final bytesLeft = state.totalBytes - state.completedBytes;
    if (bytesLeft <= 0) return '0s';
    final speedBytesPerSec = state.completedBytes / 3;
    if (speedBytesPerSec <= 0) return '--';
    final seconds = (bytesLeft / speedBytesPerSec).round();
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins}m ${secs}s';
  }

  static List<TransferFile> derivedOutgoingFiles(SendTransferState state) {
    if (state.outgoingFiles.isNotEmpty) {
      return state.outgoingFiles;
    }
    return state.selectedAttachments
        .map(
          (a) => TransferFile(
            fileId: a.name,
            name: a.name,
            size: a.size,
            sha256: '',
            storagePath: '',
            progress: 0,
            status: TransferFileStatus.pending,
            localSavedPath: null,
          ),
        )
        .toList(growable: false);
  }

  static String statusLabel(SendTransferStatus status) {
    switch (status) {
      case SendTransferStatus.drafting:
        return 'Drafting';
      case SendTransferStatus.validating:
        return 'Validating recipient';
      case SendTransferStatus.uploading:
        return 'Uploading';
      case SendTransferStatus.sent:
        return 'Sent';
      case SendTransferStatus.failed:
        return 'Failed';
      case SendTransferStatus.cancelled:
        return 'Cancelled';
    }
  }
}
