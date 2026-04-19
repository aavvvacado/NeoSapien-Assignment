part of 'incoming_transfer_bloc.dart';

sealed class IncomingTransferEvent extends Equatable {
  const IncomingTransferEvent();

  @override
  List<Object?> get props => [];
}

class ObserveIncomingStarted extends IncomingTransferEvent {
  const ObserveIncomingStarted();
}

class IncomingTransfersUpdated extends IncomingTransferEvent {
  const IncomingTransfersUpdated(this.transfers);
  final List<Transfer> transfers;

  @override
  List<Object?> get props => [transfers];
}

class IncomingObserveFailed extends IncomingTransferEvent {
  const IncomingObserveFailed(this.errorMessage);
  final String errorMessage;

  @override
  List<Object?> get props => [errorMessage];
}

class DownloadTransferRequested extends IncomingTransferEvent {
  const DownloadTransferRequested(this.transferId);
  final String transferId;

  @override
  List<Object?> get props => [transferId];
}

class DeclineTransferRequested extends IncomingTransferEvent {
  const DeclineTransferRequested(this.transferId);
  final String transferId;

  @override
  List<Object?> get props => [transferId];
}

class ClearDownloadHandoff extends IncomingTransferEvent {
  const ClearDownloadHandoff();
}
