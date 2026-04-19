import 'package:neosapien_assignment/core/result/result.dart';
import 'package:neosapien_assignment/features/identity/domain/entities/user_identity.dart';
import 'package:neosapien_assignment/features/identity/domain/repositories/identity_repository.dart';

class BootstrapIdentityUseCase {
  const BootstrapIdentityUseCase(this._repository);

  final IdentityRepository _repository;

  Future<Result<UserIdentity>> call() => _repository.bootstrapIdentity();
}
