import 'package:equatable/equatable.dart';

enum TransferFileStatus { pending, uploading, downloading, completed, failed }

class TransferFile extends Equatable {
  const TransferFile({
    required this.fileId,
    required this.name,
    required this.size,
    required this.sha256,
    required this.storagePath,
    required this.progress,
    required this.status,
    this.localSavedPath,
  });

  final String fileId;
  final String name;
  final int size;
  final String sha256;
  final String storagePath;
  final double progress;
  final TransferFileStatus status;
  final String? localSavedPath;

  @override
  List<Object?> get props => [
        fileId,
        name,
        size,
        sha256,
        storagePath,
        progress,
        status,
        localSavedPath,
      ];
}
