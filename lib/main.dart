import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:neosapien_assignment/app/app.dart';
import 'package:neosapien_assignment/app/bootstrap.dart';
import 'package:neosapien_assignment/core/platform/android_incoming_notification_service.dart';
import 'package:neosapien_assignment/di/service_locator.dart';

import 'core/services/cache_cleanup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Optional local env file.
  }
  await bootstrapSupabase();
  await setupServiceLocator();
  String? initialTransferId;
  try {
    initialTransferId = await getIt<AndroidIncomingNotificationService>()
        .consumeInitialTransferId();
  } catch (_) {
    initialTransferId = null;
  }
  if (Platform.isAndroid) {
    try {
      await getIt<AndroidIncomingNotificationService>()
          .requestNotificationPermission();
    } catch (_) {}
  }

  // Trigger cache cleanup on startup
  try {
    await getIt<CacheCleanupService>().cleanup();
  } catch (_) {}

  runApp(NeoSapienApp(initialTransferId: initialTransferId));
}
