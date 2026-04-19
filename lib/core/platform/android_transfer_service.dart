import 'dart:io';

import 'package:flutter/services.dart';

class AndroidTransferService {
  static const MethodChannel _channel =
      MethodChannel('neosapien/native_bridge');

  Future<void> start({
    required String title,
    required String message,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('startForegroundTransfer', {
      'title': title,
      'message': message,
    });
  }

  Future<void> update({
    required String title,
    required String message,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('updateForegroundTransfer', {
      'title': title,
      'message': message,
    });
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('stopForegroundTransfer');
  }
}
