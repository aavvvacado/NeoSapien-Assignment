import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class NativePickedFile {
  const NativePickedFile({
    required this.path,
    required this.name,
    required this.size,
    this.mimeType,
  });

  final String path;
  final String name;
  final int size;
  final String? mimeType;
}

class NativeDownloadSaver {
  static const MethodChannel _channel = MethodChannel(
    'neosapien/native_bridge',
  );

  Future<String> saveToDeviceDownloads({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'bytes': bytes,
        'mimeType': mimeType ?? _guessMimeType(fileName),
      });
      if (result == null || result.isEmpty) {
        throw StateError('Native save returned no location');
      }
      return result;
    }
    throw UnsupportedError('Native downloads save is Android-first only');
  }

  Future<String> saveFileToDeviceDownloads({
    required String fileName,
    required String sourcePath,
    String? mimeType,
  }) async {
    if (Platform.isAndroid) {
      final result = await _channel
          .invokeMethod<String>('saveToDownloadsFromPath', {
            'fileName': fileName,
            'sourcePath': sourcePath,
            'mimeType': mimeType ?? _guessMimeType(fileName),
          });
      if (result == null || result.isEmpty) {
        throw StateError('Native save returned no location');
      }
      return result;
    }
    throw UnsupportedError('Native downloads save is Android-first only');
  }

  Future<List<NativePickedFile>> pickFilesAndroid() async {
    if (!Platform.isAndroid) {
      return const [];
    }
    final result = await _channel.invokeMethod<List<dynamic>>('pickFiles');
    if (result == null) {
      return const [];
    }
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => NativePickedFile(
            path: (item['path'] ?? '') as String,
            name: (item['name'] ?? '') as String,
            size: (item['size'] ?? 0) as int,
            mimeType:
                (item['mimeType'] as String?) ??
                guessMimeTypeForPicker((item['name'] ?? '') as String),
          ),
        )
        .where((item) => item.path.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> sharePathOrUri({
    required String pathOrUri,
    required String title,
    String? fileName,
    String? mimeType,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('shareFile', {
      'pathOrUri': pathOrUri,
      'mimeType': mimeType ?? _guessMimeType(fileName ?? pathOrUri),
      'title': title,
      'fileName': fileName ?? '',
    });
  }

  /// Opens a saved download (content [Uri] or absolute file path) in the default viewer.
  Future<void> openUriForView({
    required String pathOrUri,
    required String fileName,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('openUriForView', {
      'pathOrUri': pathOrUri,
      'fileName': fileName,
      'mimeType': _guessMimeType(fileName),
    });
  }

  Future<int?> getAvailableDownloadBytes() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final value = await _channel.invokeMethod<int>('getAvailableDownloadBytes');
    return value;
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
    } catch (e) {
      // Fallback or ignore if not supported
    }
  }

  String guessMimeTypeForPicker(String fileName) {
    return _guessMimeType(fileName);
  }

  String _guessMimeType(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heif';
      case '.heif':
        return 'image/heif';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.mkv':
        return 'video/x-matroska';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.m4a':
        return 'audio/mp4';
      case '.ogg':
        return 'audio/ogg';
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.zip':
        return 'application/zip';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  /// Resolves a unique file path by appending (1), (2), etc. if the file already exists.
  Future<File> resolveUniqueFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return file;
    }

    final dir = p.dirname(path);
    final fileName = p.basename(path);
    final ext = p.extension(fileName);
    final nameWithoutExt = p.basenameWithoutExtension(fileName);

    int counter = 1;
    while (true) {
      final newPath = p.join(dir, '$nameWithoutExt ($counter)$ext');
      final newFile = File(newPath);
      if (!await newFile.exists()) {
        return newFile;
      }
      counter++;
    }
  }
}
