import 'package:neosapien_assignment/core/constants/app_constants.dart';
import 'package:neosapien_assignment/core/error/failure.dart';
import 'package:neosapien_assignment/core/result/result.dart';
import 'package:neosapien_assignment/core/utils/short_code_input_validator.dart';
import 'package:neosapien_assignment/features/files/data/local_file_picker_service.dart';
import 'package:neosapien_assignment/features/transfer/data/datasources/supabase_transfer_datasource.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/incoming_download_summary.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/picked_attachment_meta.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/domain/repositories/transfer_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransferRepositoryImpl implements TransferRepository {
  TransferRepositoryImpl({
    required SupabaseTransferDataSource dataSource,
    required LocalFilePickerService picker,
    required SupabaseClient supabaseClient,
  })  : _dataSource = dataSource,
        _picker = picker,
        _supabaseClient = supabaseClient;

  final SupabaseTransferDataSource _dataSource;
  final LocalFilePickerService _picker;
  final SupabaseClient _supabaseClient;

  @override
  Future<Result<List<PickedAttachmentMeta>>> pickFiles() async {
    final files = await _picker.pickMultiple();
    if (files.isEmpty) {
      return Result.fail(const ValidationFailure('No files selected'));
    }
    final totalSize = files.fold<int>(0, (acc, item) => acc + item.size);
    if (totalSize > AppConstants.maxTransferSizeBytes) {
      return Result.fail(
        StorageFailure(
          'Selected files exceed ${AppConstants.maxTransferSizeBytes ~/ (1024 * 1024)} MB limit',
        ),
      );
    }
    _dataSource.selectedFiles = files;
    return Result.success(
      files
          .map((file) => PickedAttachmentMeta(
                name: file.name,
                size: file.size,
                path: file.path,
              ))
          .toList(growable: false),
    );
  }

  @override
  Future<Result<String>> startTransfer(String recipientCode) async {
    try {
      final senderUid = _supabaseClient.auth.currentUser?.id;
      if (senderUid == null) {
        return Result.fail(const ValidationFailure('Identity is not ready yet'));
      }
      final normalized = ShortCodeInputValidator.normalize(recipientCode);
      if (!ShortCodeInputValidator.syntaxValidForLookup(normalized)) {
        return Result.fail(
          ValidationFailure(ShortCodeInputValidator.syntaxInvalidUserMessage()),
        );
      }
      final transferId = await _dataSource.createTransfer(
        senderUid: senderUid,
        recipientCode: normalized,
      );
      return Result.success(transferId);
    } on StateError catch (e) {
      if (e.message == 'invalid_recipient_code') {
        return Result.fail(const NotFoundFailure('Invalid recipient code'));
      }
      if (e.message == 'self_send_not_allowed') {
        return Result.fail(
          const ValidationFailure(
            'You cannot send files to your own code. Use the other device’s code.',
          ),
        );
      }
      return Result.fail(ValidationFailure(e.message.toString()));
    } catch (e) {
      return Result.fail(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> uploadSelectedFiles() async {
    try {
      await _dataSource.uploadFiles();
      return Result.success(null);
    } catch (e) {
      return Result.fail(UnknownFailure(e.toString()));
    }
  }

  @override
  Stream<List<Transfer>> observeIncomingTransfers() {
    final uid = _supabaseClient.auth.currentUser?.id;
    if (uid == null) {
      return const Stream.empty();
    }
    return _dataSource.observeIncoming(uid);
  }

  @override
  Stream<Transfer?> observeTransferById(String transferId) {
    return _dataSource.observeTransferById(transferId);
  }

  @override
  Future<Result<void>> cancelTransfer(String transferId) async {
    try {
      await _dataSource.cancelTransfer(transferId);
      return Result.success(null);
    } catch (e) {
      return Result.fail(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Transfer?> fetchTransferById(String transferId) =>
      _dataSource.fetchTransferById(transferId);

  @override
  Future<Result<IncomingDownloadSummary>> downloadTransfer(String transferId) async {
    try {
      final summary = await _dataSource.downloadIncomingTransfer(transferId);
      return Result.success(summary);
    } on StateError catch (e) {
      return Result.fail(ValidationFailure(e.message.toString()));
    } catch (e) {
      return Result.fail(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<void> registerExternalFiles(List<PickedAttachmentMeta> files) async {
    _dataSource.selectedFiles = files.map((meta) => PickedLocalFile(
      name: meta.name,
      size: meta.size,
      path: meta.path,
    )).toList();
  }

  @override
  Future<void> fetchIncomingTransfers() async {
    final uid = _supabaseClient.auth.currentUser?.id;
    if (uid != null) {
      await _dataSource.fetchIncomingTransfersFor(uid);
    }
  }
}
