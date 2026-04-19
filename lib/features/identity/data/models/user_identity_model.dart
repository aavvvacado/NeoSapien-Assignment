import 'package:neosapien_assignment/features/identity/domain/entities/user_identity.dart';

class UserIdentityModel extends UserIdentity {
  const UserIdentityModel({
    required super.uid,
    required super.shortCode,
    required super.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'short_code': shortCode,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  factory UserIdentityModel.fromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['created_at'];
    return UserIdentityModel(
      uid: map['uid'] as String,
      shortCode: (map['short_code'] ?? map['shortCode']) as String,
      createdAt: createdAtRaw is String
          ? DateTime.tryParse(createdAtRaw)?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
