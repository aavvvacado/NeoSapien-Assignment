part of 'identity_bloc.dart';

sealed class IdentityEvent extends Equatable {
  const IdentityEvent();

  @override
  List<Object?> get props => [];
}

class BootstrapIdentity extends IdentityEvent {
  const BootstrapIdentity();
}
