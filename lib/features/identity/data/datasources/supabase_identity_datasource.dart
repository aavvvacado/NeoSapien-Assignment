import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:neosapien_assignment/core/utils/short_code_generator.dart';
import 'package:neosapien_assignment/features/identity/data/models/user_identity_model.dart';

class SupabaseIdentityDataSource {
  const SupabaseIdentityDataSource({
    required SupabaseClient supabaseClient,
    required SharedPreferences prefs,
  })  : _supabaseClient = supabaseClient,
        _prefs = prefs;

  final SupabaseClient _supabaseClient;
  final SharedPreferences _prefs;

  static const _cachedShortCodeKey = 'identity.shortCode';

  Future<UserIdentityModel> bootstrapIdentity() async {
    final user = await _ensureUser();
    final userId = user.id;
    final cachedCode = _prefs.getString(_cachedShortCodeKey);
    late final String resolvedCode;

    if (cachedCode != null) {
      resolvedCode = await _restoreOrReassignCode(cachedCode, userId);
    } else {
      final users = await _supabaseClient
          .from('users')
          .select('uid, short_code, created_at')
          .eq('uid', userId)
          .limit(1);

      if (users.isNotEmpty && users.first['short_code'] != null) {
        final codeFromUserDoc = users.first['short_code'] as String;
        resolvedCode = await _restoreOrReassignCode(codeFromUserDoc, userId);
      } else {
        resolvedCode = await _claimShortCode(userId);
      }
    }

    // Keep insert order compatible with FK short_codes.uid -> users.uid.
    await _upsertUser(userId, resolvedCode);
    await _upsertShortCode(resolvedCode, userId);
    await _prefs.setString(_cachedShortCodeKey, resolvedCode);
    return UserIdentityModel(
      uid: userId,
      shortCode: resolvedCode,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _upsertUser(String uid, String shortCode) async {
    await _supabaseClient.from('users').upsert({
      'uid': uid,
      'short_code': shortCode,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _upsertShortCode(String code, String uid) async {
    await _supabaseClient.from('short_codes').upsert({
      'code': code,
      'uid': uid,
      'reserved_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> _restoreOrReassignCode(String candidateCode, String uid) async {
    final rows = await _supabaseClient
        .from('short_codes')
        .select('uid')
        .eq('code', candidateCode)
        .limit(1);

    if (rows.isEmpty || rows.first['uid'] == uid) {
      return candidateCode;
    }

    return _claimShortCode(uid);
  }

  Future<User> _ensureUser() async {
    if (_supabaseClient.auth.currentUser != null) {
      return _supabaseClient.auth.currentUser!;
    }
    final response = await _supabaseClient.auth.signInAnonymously();
    final user = response.user;
    if (user == null) {
      throw StateError('Unable to establish Supabase anonymous user');
    }
    return user;
  }

  Future<String> _claimShortCode(String uid) async {
    // Keep this reservation local until users row is persisted to satisfy FK order.
    final claimedByUid = uid;
    for (int i = 0; i < 15; i++) {
      final code = ShortCodeGenerator.generate();
      final existing = await _supabaseClient
          .from('short_codes')
          .select('code')
          .eq('code', code)
          .limit(1);
      if (existing.isEmpty) {
        if (claimedByUid.isEmpty) {
          throw StateError('invalid_uid');
        }
        return code;
      }
    }
    throw TimeoutException('Could not claim a short code after retries');
  }
}
