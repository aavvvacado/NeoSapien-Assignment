part of 'incoming_transfer_bloc.dart';

class IncomingTransferState extends Equatable {
  const IncomingTransferState({
    required this.transfers,
    required this.message,
    required this.lastSyncAt,
    required this.syncError,
    this.downloadHandoff,
  });

  const IncomingTransferState.initial()
      : transfers = const [],
        message = '',
        lastSyncAt = null,
        syncError = '',
        downloadHandoff = null;

  final List<Transfer> transfers;
  final String message;
  final DateTime? lastSyncAt;
  final String syncError;
  final IncomingDownloadSummary? downloadHandoff;

  IncomingTransferState copyWith({
    List<Transfer>? transfers,
    String? message,
    DateTime? lastSyncAt,
    String? syncError,
    IncomingDownloadSummary? downloadHandoff,
    bool clearDownloadHandoff = false,
  }) {
    return IncomingTransferState(
      transfers: transfers ?? this.transfers,
      message: message ?? this.message,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      syncError: syncError ?? this.syncError,
      downloadHandoff:
          clearDownloadHandoff ? null : (downloadHandoff ?? this.downloadHandoff),
    );
  }

  @override
  List<Object?> get props => [transfers, message, lastSyncAt, syncError, downloadHandoff];
}
