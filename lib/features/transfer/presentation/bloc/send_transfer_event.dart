part of 'send_transfer_bloc.dart';

sealed class SendTransferEvent extends Equatable {
  const SendTransferEvent();

  @override
  List<Object?> get props => [];
}

class RecipientCodeChanged extends SendTransferEvent {
  const RecipientCodeChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

class PickFilesRequested extends SendTransferEvent {
  const PickFilesRequested();
}

class StartUploadRequested extends SendTransferEvent {
  const StartUploadRequested({this.ignoreCellularWarning = false});
  final bool ignoreCellularWarning;

  @override
  List<Object?> get props => [ignoreCellularWarning];
}

class CancelTransferRequested extends SendTransferEvent {
  const CancelTransferRequested();
}

class OutgoingTransferUpdated extends SendTransferEvent {
  const OutgoingTransferUpdated(this.transfer);
  final Transfer transfer;

  @override
  List<Object?> get props => [transfer];
}

class ExternalFilesReceived extends SendTransferEvent {
  const ExternalFilesReceived(this.files);
  final List<PickedAttachmentMeta> files;

  @override
  List<Object?> get props => [files];
}
