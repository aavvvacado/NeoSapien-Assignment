part of 'identity_bloc.dart';

sealed class IdentityState extends Equatable {
  const IdentityState();

  @override
  List<Object?> get props => [];
}

class IdentityLoading extends IdentityState {
  const IdentityLoading();
}

class IdentityReady extends IdentityState {
  const IdentityReady(this.identity);

  final UserIdentity identity;

  @override
  List<Object?> get props => [identity];
}

class IdentityError extends IdentityState {
  const IdentityError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
