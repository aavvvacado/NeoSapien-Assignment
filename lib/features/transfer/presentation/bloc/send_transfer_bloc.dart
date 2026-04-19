import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:neosapien_assignment/core/platform/android_incoming_notification_service.dart';
import 'package:neosapien_assignment/core/utils/app_error_mapper.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/picked_attachment_meta.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer_file.dart';
import 'package:neosapien_assignment/features/transfer/domain/repositories/transfer_repository.dart';

import '../../../../core/utils/transfer_user_messages.dart';
import '../../domain/usecases/send_transfer_usecase.dart';

part 'send_transfer_event.dart';
part 'send_transfer_state.dart';

class SendTransferBloc extends Bloc<SendTransferEvent, SendTransferState> {
  SendTransferBloc(this._sendTransferUseCase, this._repository, this._headsUp)
    : super(const SendTransferState.initial()) {
    on<RecipientCodeChanged>(_onRecipientCodeChanged);
    on<PickFilesRequested>(_onPickFilesRequested);
    on<StartUploadRequested>(_onStartUploadRequested);
    on<CancelTransferRequested>(_onCancelTransferRequested);
    on<OutgoingTransferUpdated>(_onOutgoingTransferUpdated);
    on<ExternalFilesReceived>(_onExternalFilesReceived);
  }

  final SendTransferUseCase _sendTransferUseCase;
  final TransferRepository _repository;
  final AndroidIncomingNotificationService _headsUp;
  StreamSubscription<Transfer?>? _outgoingSubscription;

  void _onRecipientCodeChanged(
    RecipientCodeChanged event,
    Emitter<SendTransferState> emit,
  ) {
    String? currentMessage = state.message;
    if (state.selectedAttachments.isNotEmpty &&
        (currentMessage == null ||
            currentMessage.isEmpty ||
            currentMessage.startsWith('Transfer'))) {
      currentMessage = '${state.selectedAttachments.length} file(s) selected';
    }
    emit(
      state.copyWith(
        recipientCode: event.value,
        message: currentMessage,
        // Force a new `createTransfer` + lookup when the code changes (avoids
        // reusing a previous transfer id after editing the recipient field).
        activeTransferId: '',
      ),
    );
  }

  Future<void> _onPickFilesRequested(
    PickFilesRequested event,
    Emitter<SendTransferState> emit,
  ) async {
    final result = await _repository.pickFiles();
    if (result.isFailure) {
      emit(
        state.copyWith(
          status: SendTransferStatus.failed,
          message: result.failure!.message,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: SendTransferStatus.drafting,
        message: '${result.value!.length} file(s) selected',
        selectedAttachments: result.value!,
        activeTransferId:
            '', // Use empty string to signal nulling out if your copyWith doesn't support explicit nulls well, or just let startTransfer overwrite it.
      ),
    );
  }

  void _onExternalFilesReceived(
    ExternalFilesReceived event,
    Emitter<SendTransferState> emit,
  ) {
    unawaited(_repository.registerExternalFiles(event.files));
    emit(
      state.copyWith(
        status: SendTransferStatus.drafting,
        message: '${event.files.length} file(s) shared to NeoSapien',
        selectedAttachments: event.files,
      ),
    );
  }

  Future<void> _onStartUploadRequested(
    StartUploadRequested event,
    Emitter<SendTransferState> emit,
  ) async {
    final localTotal = state.selectedAttachments.fold<int>(
      0,
      (sum, item) => sum + item.size,
    );

    // Check for cellular data warning if transfer is > 400MB
    const largeTransferThreshold = 400 * 1024 * 1024;
    final connectivity = await Connectivity().checkConnectivity();
    if (!event.ignoreCellularWarning &&
        connectivity.contains(ConnectivityResult.mobile) &&
        localTotal > largeTransferThreshold) {
      emit(
        state.copyWith(
          status: SendTransferStatus.drafting,
          message: 'LARGE_TRANSFER_ON_CELLULAR',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: SendTransferStatus.validating,
        message: 'Validating recipient...',
      ),
    );

    // Basic rate-limiting delay to prevent high-speed enumeration
    await Future.delayed(const Duration(seconds: 1));

    String? tId = state.activeTransferId;
    if (tId == null || tId.isEmpty) {
      final created = await _sendTransferUseCase(state.recipientCode);
      if (created.isFailure) {
        unawaited(
          _headsUp.showHeadsUpStatus(
            title: 'Send failed',
            body: TransferUserMessages.describe(created.failure!.message),
            notificationId: 7810,
          ),
        );
        final friendlyError = AppErrorMapper.map(created.failure!.message);
        emit(
          state.copyWith(
            status: SendTransferStatus.failed,
            message: friendlyError,
          ),
        );
        return;
      }
      tId = created.value;
    }

    final syntheticFiles = _syntheticUploadRows(state.selectedAttachments);
    emit(
      state.copyWith(
        status: SendTransferStatus.uploading,
        activeTransferId: tId,
        message: 'Uploading...',
        totalBytes: localTotal,
        completedBytes: 0,
        transferProgress: 0,
        outgoingFiles: syntheticFiles,
        lastSyncAt: DateTime.now(),
      ),
    );
    await _outgoingSubscription?.cancel();
    _outgoingSubscription = _repository.observeTransferById(tId!).listen((
      transfer,
    ) {
      if (transfer != null) {
        add(OutgoingTransferUpdated(transfer));
      }
    });
    final uploaded = await _repository.uploadSelectedFiles();
    if (uploaded.isFailure) {
      unawaited(
        _headsUp.showHeadsUpStatus(
          title: 'Upload failed',
          body: TransferUserMessages.describe(uploaded.failure!.message),
          notificationId: 7811,
        ),
      );
      final friendlyError = AppErrorMapper.map(uploaded.failure!.message);
      emit(
        state.copyWith(
          status: SendTransferStatus.failed,
          message: friendlyError,
        ),
      );
      return;
    }
    final fresh = await _repository.fetchTransferById(tId!);
    unawaited(
      _headsUp.showHeadsUpStatus(
        title: 'Transfer sent',
        body: 'Your files were delivered to the recipient',
        notificationId: 7812,
      ),
    );
    emit(
      state.copyWith(
        status: SendTransferStatus.sent,
        message: 'Transfer sent successfully',
        transferProgress: fresh?.progress.clamp(0.0, 1.0) ?? 1.0,
        totalBytes: fresh?.totalBytes ?? state.totalBytes,
        completedBytes: fresh?.completedBytes ?? state.completedBytes,
        outgoingFiles: fresh?.files ?? state.outgoingFiles,
        selectedAttachments: const [],
        lastSyncAt: DateTime.now(),
        activeTransferId: '',
      ),
    );
  }

  Future<void> _onCancelTransferRequested(
    CancelTransferRequested event,
    Emitter<SendTransferState> emit,
  ) async {
    if (state.activeTransferId == null) {
      return;
    }
    await _repository.cancelTransfer(state.activeTransferId!);
    emit(
      state.copyWith(
        status: SendTransferStatus.cancelled,
        message: 'Transfer cancelled',
      ),
    );
  }

  void _onOutgoingTransferUpdated(
    OutgoingTransferUpdated event,
    Emitter<SendTransferState> emit,
  ) {
    final transfer = event.transfer;
    var status = state.status;
    if (transfer.status == TransferStatus.failed) {
      status = SendTransferStatus.failed;
    } else if (transfer.status == TransferStatus.cancelled) {
      status = SendTransferStatus.cancelled;
    } else if (transfer.status == TransferStatus.uploaded ||
        transfer.status == TransferStatus.notifying ||
        transfer.status == TransferStatus.completed) {
      status = SendTransferStatus.sent;
    } else if (transfer.status == TransferStatus.uploading ||
        transfer.status == TransferStatus.initiated) {
      status = SendTransferStatus.uploading;
    }

    emit(
      state.copyWith(
        status: status,
        transferProgress: transfer.progress.clamp(0.0, 1.0),
        totalBytes: transfer.totalBytes > 0
            ? transfer.totalBytes
            : state.totalBytes,
        completedBytes: transfer.completedBytes,
        outgoingFiles: transfer.files.isNotEmpty
            ? transfer.files
            : state.outgoingFiles,
        lastSyncAt: DateTime.now(),
      ),
    );
  }

  List<TransferFile> _syntheticUploadRows(List<PickedAttachmentMeta> items) {
    return items
        .map(
          (a) => TransferFile(
            fileId: 'local:${a.name}',
            name: a.name,
            size: a.size,
            sha256: '',
            storagePath: '',
            progress: 0,
            status: TransferFileStatus.uploading,
            localSavedPath: null,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> close() async {
    await _outgoingSubscription?.cancel();
    return super.close();
  }
}
