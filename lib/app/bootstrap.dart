import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:neosapien_assignment/core/logging/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool isSupabaseReady = false;

Future<void> bootstrapSupabase() async {
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ??
      const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ??
      const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    AppLogger.warn(
      'Supabase env not provided. Pass --dart-define SUPABASE_URL and SUPABASE_ANON_KEY.',
    );
    isSupabaseReady = false;
    return;
  }

  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    isSupabaseReady = true;
    AppLogger.info('Supabase initialized');
  } catch (error, stackTrace) {
    isSupabaseReady = false;
    AppLogger.warn('Supabase initialization failed. Uploads may fail.');
    AppLogger.error('bootstrapSupabase', error, stackTrace);
  }
}
