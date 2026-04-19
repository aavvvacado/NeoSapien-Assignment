import 'package:neosapien_assignment/core/result/result.dart';
import 'package:neosapien_assignment/features/transfer/domain/repositories/transfer_repository.dart';

class SendTransferUseCase {
  const SendTransferUseCase(this._repository);

  final TransferRepository _repository;

  Future<Result<String>> call(String recipientCode) => _repository.startTransfer(recipientCode);
}
