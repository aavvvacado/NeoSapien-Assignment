import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';

class CacheCleanupService {
  const CacheCleanupService();

  /// Cleans up stale temporary files in the application documents directory.
  /// Files older than [staleDuration] will be deleted.
  Future<void> cleanup({
    Duration staleDuration = const Duration(hours: 24),
  }) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      if (!await docDir.exists()) return;

      final now = DateTime.now();
      final entities = docDir.listSync();

      int deletedCount = 0;
      for (final entity in entities) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);

          // Delete if it's a temporary working file or if it's older than staleDuration
          final isWorkingFile =
              entity.path.contains('working_file_') ||
              entity.path.contains('lan_tmp_');

          if (isWorkingFile || age > staleDuration) {
            await entity.delete();
            deletedCount++;
          }
        }
      }
      AppLogger.info(
        'CacheCleanupService: Deleted $deletedCount stale temporary files.',
      );
    } catch (e, st) {
      AppLogger.error('CacheCleanupService', e, st);
    }
  }
}
