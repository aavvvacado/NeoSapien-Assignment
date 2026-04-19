import 'package:neosapien_assignment/core/error/failure.dart';
import 'package:neosapien_assignment/core/result/result.dart';
import 'package:neosapien_assignment/features/identity/data/datasources/supabase_identity_datasource.dart';
import 'package:neosapien_assignment/features/identity/domain/entities/user_identity.dart';
import 'package:neosapien_assignment/features/identity/domain/repositories/identity_repository.dart';

class IdentityRepositoryImpl implements IdentityRepository {
  const IdentityRepositoryImpl(this._dataSource);

  final SupabaseIdentityDataSource _dataSource;

  @override
  Future<Result<UserIdentity>> bootstrapIdentity() async {
    try {
      final identity = await _dataSource.bootstrapIdentity();
      return Result.success(identity);
    } on StateError catch (e) {
      return Result.fail(ValidationFailure(e.message.toString()));
    } catch (e) {
      return Result.fail(UnknownFailure(e.toString()));
    }
  }
}
