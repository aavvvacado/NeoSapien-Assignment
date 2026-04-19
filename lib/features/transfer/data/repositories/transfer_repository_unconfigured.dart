import 'package:neosapien_assignment/core/error/failure.dart';
import 'package:neosapien_assignment/core/result/result.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/incoming_download_summary.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/picked_attachment_meta.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/domain/repositories/transfer_repository.dart';

class TransferRepositoryUnconfigured implements TransferRepository {
  const TransferRepositoryUnconfigured();

  static const String _message =
      'Supabase is not configured. Run with --dart-define SUPABASE_URL and SUPABASE_ANON_KEY.';

  @override
  Future<Result<void>> cancelTransfer(String transferId) async {
    return Result.fail(const ValidationFailure(_message));
  }

  @override
  Future<Result<IncomingDownloadSummary>> downloadTransfer(String transferId) async {
    return Result.fail(const ValidationFailure(_message));
  }

  @override
  Stream<List<Transfer>> observeIncomingTransfers() {
    return const Stream.empty();
  }

  @override
  Stream<Transfer?> observeTransferById(String transferId) {
    return const Stream.empty();
  }


  @override
  Future<Result<List<PickedAttachmentMeta>>> pickFiles() async {
    return Result.fail(const ValidationFailure(_message));
  }

  @override
  Future<Transfer?> fetchTransferById(String transferId) async => null;

  @override
  Future<Result<String>> startTransfer(String recipientCode) async {
    return Result.fail(const ValidationFailure(_message));
  }

  @override
  Future<Result<void>> uploadSelectedFiles() async {
    return Result.fail(const ValidationFailure(_message));
  }

  @override
  Future<void> fetchIncomingTransfers() async {
    // No-op in unconfigured state
  }

  @override
  Future<void> registerExternalFiles(List<PickedAttachmentMeta> files) async {
    // No-op in unconfigured state
  }
}
