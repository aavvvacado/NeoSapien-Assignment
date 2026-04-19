import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/domain/repositories/transfer_repository.dart';

class ObserveIncomingTransfersUseCase {
  const ObserveIncomingTransfersUseCase(this._repository);

  final TransferRepository _repository;

  Stream<List<Transfer>> call() => _repository.observeIncomingTransfers();
}
