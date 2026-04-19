import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:neosapien_assignment/core/platform/android_incoming_notification_service.dart';
import 'package:neosapien_assignment/core/utils/transfer_user_messages.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/incoming_download_summary.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/domain/repositories/transfer_repository.dart';
import 'package:neosapien_assignment/features/transfer/domain/usecases/observe_incoming_transfers_usecase.dart';

part 'incoming_transfer_event.dart';
part 'incoming_transfer_state.dart';

class IncomingTransferBloc extends Bloc<IncomingTransferEvent, IncomingTransferState> {
  IncomingTransferBloc(
    this._observeIncomingTransfersUseCase,
    this._repository,
    this._incomingNotificationService,
  )
      : super(const IncomingTransferState.initial()) {
    on<ObserveIncomingStarted>(_onObserveIncomingStarted);
    on<IncomingTransfersUpdated>(_onIncomingTransfersUpdated);
    on<IncomingObserveFailed>(_onIncomingObserveFailed);
    on<DownloadTransferRequested>(_onDownloadTransferRequested);
    on<DeclineTransferRequested>(_onDeclineTransferRequested);
    on<ClearDownloadHandoff>(_onClearDownloadHandoff);
  }

  final ObserveIncomingTransfersUseCase _observeIncomingTransfersUseCase;
  final TransferRepository _repository;
  final AndroidIncomingNotificationService _incomingNotificationService;
  StreamSubscription<List<Transfer>>? _subscription;
  final Set<String> _notifiedTransferIds = <String>{};
  bool _isDownloadingGlobally = false;
  Timer? _heartbeat;

  Future<void> _onObserveIncomingStarted(
    ObserveIncomingStarted event,
    Emitter<IncomingTransferState> emit,
  ) async {
    await _subscription?.cancel();
    _heartbeat?.cancel();

    _subscription = _observeIncomingTransfersUseCase().listen(
      (items) {
        add(IncomingTransfersUpdated(items));
      },
      onError: (error, _) {
        add(IncomingObserveFailed(error.toString()));
      },
    );

    // Heartbeat fallback: Force a refresh every 5 seconds if we are active
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isClosed) {
        // We trigger ObserveIncomingStarted again to re-sync, 
        // but that might be overkill. Better to add a Refresh event.
        // For now, many snapshots are fine in Supabase.
        _repository.fetchIncomingTransfers(); 
      }
    });
  }

  Future<void> _onDownloadTransferRequested(
    DownloadTransferRequested event,
    Emitter<IncomingTransferState> emit,
  ) async {
    if (_isDownloadingGlobally) {
      emit(state.copyWith(message: 'Please wait for the current download to finish.'));
      return; 
    }
    _isDownloadingGlobally = true;

    emit(state.copyWith(message: 'Downloading...'));
    unawaited(
      _incomingNotificationService.showHeadsUpStatus(
        title: 'Downloading',
        body: 'Saving files to Downloads…',
      ),
    );
    try {
      final result = await _repository.downloadTransfer(event.transferId);
      if (result.isFailure) {
        final friendly = TransferUserMessages.describeFailureMessage(result.failure!.message);
        unawaited(
          _incomingNotificationService.showHeadsUpStatus(
            title: 'Download failed',
            body: friendly,
            notificationId: 7802,
          ),
        );
        emit(state.copyWith(message: friendly, clearDownloadHandoff: true));
        return;
      }
      final summary = result.value!;
      final primary = summary.primaryIfAny;
      if (primary != null) {
        unawaited(
          _incomingNotificationService.showDownloadSavedNotification(
            fileName: primary.fileName,
            openUriOrPath: primary.openUriOrPath,
          ),
        );
      }
      emit(
        state.copyWith(
          message: '',
          downloadHandoff: summary,
          lastSyncAt: DateTime.now(),
        ),
      );
    } finally {
      _isDownloadingGlobally = false;
    }
  }

  void _onClearDownloadHandoff(
    ClearDownloadHandoff event,
    Emitter<IncomingTransferState> emit,
  ) {
    emit(state.copyWith(clearDownloadHandoff: true));
  }

  Future<void> _onDeclineTransferRequested(
    DeclineTransferRequested event,
    Emitter<IncomingTransferState> emit,
  ) async {
    final result = await _repository.cancelTransfer(event.transferId);
    if (result.isFailure) {
      emit(
        state.copyWith(
          message: TransferUserMessages.describeFailureMessage(result.failure!.message),
        ),
      );
      return;
    }
    emit(state.copyWith(message: 'Transfer declined'));
  }

  void _onIncomingTransfersUpdated(
    IncomingTransfersUpdated event,
    Emitter<IncomingTransferState> emit,
  ) {
    for (final transfer in event.transfers) {
      final shouldNotify = !_notifiedTransferIds.contains(transfer.transferId) &&
          (transfer.status == TransferStatus.initiated ||
              transfer.status == TransferStatus.uploading ||
              transfer.status == TransferStatus.uploaded ||
              transfer.status == TransferStatus.notifying);
      if (shouldNotify) {
        if (transfer.files.isEmpty) continue;
        _notifiedTransferIds.add(transfer.transferId);
        unawaited(
          _incomingNotificationService.showIncomingTransferNotification(
            transferId: transfer.transferId,
            senderPreview: transfer.senderUid.length > 10
                ? transfer.senderUid.substring(0, 10)
                : transfer.senderUid,
            fileCount: transfer.files.length,
          ),
        );
      }
    }
    emit(
      state.copyWith(
        transfers: event.transfers,
        message: '', // Clear any stale error messages on successful payload
        lastSyncAt: DateTime.now(),
        syncError: '',
      ),
    );
  }

  void _onIncomingObserveFailed(
    IncomingObserveFailed event,
    Emitter<IncomingTransferState> emit,
  ) {
    final detail = TransferUserMessages.describe(event.errorMessage);
    emit(
      state.copyWith(
        syncError: 'Could not refresh the transfer list. $detail',
      ),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
