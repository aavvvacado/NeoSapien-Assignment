import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:neosapien_assignment/features/identity/domain/entities/user_identity.dart';
import 'package:neosapien_assignment/features/identity/domain/usecases/bootstrap_identity_usecase.dart';

part 'identity_event.dart';
part 'identity_state.dart';

class IdentityBloc extends Bloc<IdentityEvent, IdentityState> {
  IdentityBloc(this._bootstrapIdentityUseCase) : super(const IdentityLoading()) {
    on<BootstrapIdentity>(_onBootstrapIdentity);
  }

  final BootstrapIdentityUseCase _bootstrapIdentityUseCase;

  Future<void> _onBootstrapIdentity(
    BootstrapIdentity event,
    Emitter<IdentityState> emit,
  ) async {
    emit(const IdentityLoading());
    final result = await _bootstrapIdentityUseCase();
    if (result.isFailure) {
      emit(IdentityError(result.failure!.message));
      return;
    }
    emit(IdentityReady(result.value!));
  }
}
