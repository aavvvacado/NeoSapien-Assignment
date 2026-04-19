import 'package:equatable/equatable.dart';

class UserIdentity extends Equatable {
  const UserIdentity({
    required this.uid,
    required this.shortCode,
    required this.createdAt,
  });

  final String uid;
  final String shortCode;
  final DateTime createdAt;

  @override
  List<Object?> get props => [uid, shortCode, createdAt];
}
