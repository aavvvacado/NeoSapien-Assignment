part of 'send_transfer_bloc.dart';

enum SendTransferStatus {
  drafting,
  validating,
  uploading,
  sent,
  failed,
  cancelled,
}

class SendTransferState extends Equatable {
  const SendTransferState({
    required this.status,
    required this.recipientCode,
    required this.message,
    required this.selectedAttachments,
    required this.transferProgress,
    required this.totalBytes,
    required this.completedBytes,
    required this.outgoingFiles,
    required this.lastSyncAt,
    this.activeTransferId,
  });

  const SendTransferState.initial()
      : status = SendTransferStatus.drafting,
        recipientCode = '',
        message = '',
        selectedAttachments = const [],
        transferProgress = 0,
        totalBytes = 0,
        completedBytes = 0,
        outgoingFiles = const [],
        lastSyncAt = null,
        activeTransferId = null;

  final SendTransferStatus status;
  final String recipientCode;
  final String message;
  final List<PickedAttachmentMeta> selectedAttachments;
  final double transferProgress;
  final int totalBytes;
  final int completedBytes;
  final List<TransferFile> outgoingFiles;
  final DateTime? lastSyncAt;
  final String? activeTransferId;

  SendTransferState copyWith({
    SendTransferStatus? status,
    String? recipientCode,
    String? message,
    List<PickedAttachmentMeta>? selectedAttachments,
    double? transferProgress,
    int? totalBytes,
    int? completedBytes,
    List<TransferFile>? outgoingFiles,
    DateTime? lastSyncAt,
    String? activeTransferId,
  }) {
    return SendTransferState(
      status: status ?? this.status,
      recipientCode: recipientCode ?? this.recipientCode,
      message: message ?? this.message,
      selectedAttachments: selectedAttachments ?? this.selectedAttachments,
      transferProgress: transferProgress ?? this.transferProgress,
      totalBytes: totalBytes ?? this.totalBytes,
      completedBytes: completedBytes ?? this.completedBytes,
      outgoingFiles: outgoingFiles ?? this.outgoingFiles,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      activeTransferId: activeTransferId ?? this.activeTransferId,
    );
  }

  @override
  List<Object?> get props => [
        status,
        recipientCode,
        message,
        selectedAttachments,
        transferProgress,
        totalBytes,
        completedBytes,
        outgoingFiles,
        lastSyncAt,
        activeTransferId,
      ];
}
