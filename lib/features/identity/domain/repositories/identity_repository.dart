import 'package:neosapien_assignment/core/result/result.dart';
import 'package:neosapien_assignment/features/identity/domain/entities/user_identity.dart';

abstract interface class IdentityRepository {
  Future<Result<UserIdentity>> bootstrapIdentity();
}
