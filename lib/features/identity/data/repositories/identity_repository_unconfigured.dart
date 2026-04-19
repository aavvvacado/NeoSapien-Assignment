import 'package:neosapien_assignment/core/error/failure.dart';
import 'package:neosapien_assignment/core/result/result.dart';
import 'package:neosapien_assignment/features/identity/domain/entities/user_identity.dart';
import 'package:neosapien_assignment/features/identity/domain/repositories/identity_repository.dart';

class IdentityRepositoryUnconfigured implements IdentityRepository {
  const IdentityRepositoryUnconfigured();

  @override
  Future<Result<UserIdentity>> bootstrapIdentity() async {
    return Result.fail(
      const ValidationFailure(
        'Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY.',
      ),
    );
  }
}
