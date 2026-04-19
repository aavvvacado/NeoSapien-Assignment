import 'package:equatable/equatable.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer_file.dart';

enum TransferStatus {
  initiated,
  uploading,
  uploaded,
  notifying,
  downloading,
  completed,
  failed,
  cancelled,
  expired,
}

class Transfer extends Equatable {
  const Transfer({
    required this.transferId,
    required this.senderUid,
    required this.receiverUid,
    required this.status,
    required this.files,
    required this.createdAt,
    required this.ttlExpiresAt,
    required this.totalBytes,
    required this.completedBytes,
    this.failureCode,
  });

  final String transferId;
  final String senderUid;
  final String receiverUid;
  final TransferStatus status;
  final List<TransferFile> files;
  final DateTime createdAt;
  final DateTime ttlExpiresAt;
  final int totalBytes;
  final int completedBytes;
  final String? failureCode;

  double get progress => totalBytes == 0 ? 0 : completedBytes / totalBytes;

  @override
  List<Object?> get props {
    return [
      transferId,
      senderUid,
      receiverUid,
      status,
      files,
      createdAt,
      ttlExpiresAt,
      totalBytes,
      completedBytes,
      failureCode,
    ];
  }
}
