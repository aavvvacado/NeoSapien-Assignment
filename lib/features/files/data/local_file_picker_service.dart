import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:neosapien_assignment/core/platform/native_download_saver.dart';

class PickedLocalFile {
  const PickedLocalFile({
    required this.path,
    required this.name,
    required this.size,
    this.mimeType,
  });

  final String path;
  final String name;
  final int size;
  final String? mimeType;

  bool get isZeroByte => size <= 0;
}

class LocalFilePickerService {
  const LocalFilePickerService({required NativeDownloadSaver nativeBridge})
      : _nativeBridge = nativeBridge;

  final NativeDownloadSaver _nativeBridge;

  Future<List<PickedLocalFile>> pickMultiple() async {
    if (Platform.isAndroid) {
      final picked = await _nativeBridge.pickFilesAndroid();
      if (picked.isNotEmpty) {
        return picked
            .map(
              (item) => PickedLocalFile(
                path: item.path,
                name: item.name,
                size: item.size,
                mimeType: item.mimeType,
              ),
            )
            .where((item) => !item.isZeroByte)
            .toList(growable: false);
      }
    }

    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) {
      return const [];
    }
    return result.files
        .where((item) => item.path != null)
        .map(
          (item) => PickedLocalFile(
            path: item.path!,
            name: item.name,
            size: item.size,
            mimeType: _nativeBridge.guessMimeTypeForPicker(item.name),
          ),
        )
        .where((item) => !item.isZeroByte)
        .toList(growable: false);
  }
}
