import 'dart:io';

import 'package:flutter/services.dart';

class AndroidTransferRecoveryScheduler {
  static const MethodChannel _channel =
      MethodChannel('neosapien/native_bridge');

  Future<void> enqueueRecovery({
    required String transferId,
    required String direction,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('enqueueTransferRecovery', {
      'transferId': transferId,
      'direction': direction,
    });
  }
}
