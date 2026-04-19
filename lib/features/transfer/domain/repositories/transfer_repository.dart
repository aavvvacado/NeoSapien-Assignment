import 'package:neosapien_assignment/core/result/result.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/incoming_download_summary.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/picked_attachment_meta.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';

abstract interface class TransferRepository {
  Future<Result<String>> startTransfer(String recipientCode);
  Future<Result<List<PickedAttachmentMeta>>> pickFiles();
  Future<Result<void>> uploadSelectedFiles();
  Future<Result<void>> cancelTransfer(String transferId);
  Stream<List<Transfer>> observeIncomingTransfers();
  Stream<Transfer?> observeTransferById(String transferId);
  Future<Result<IncomingDownloadSummary>> downloadTransfer(String transferId);
  Future<Transfer?> fetchTransferById(String transferId);
  Future<void> registerExternalFiles(List<PickedAttachmentMeta> files);
  Future<void> fetchIncomingTransfers();
}
