import 'dart:io';

import 'package:flutter/services.dart';

/// Android requires a multicast Wi‑Fi lock for reliable LAN discovery frames.
class AndroidMulticastLock {
  AndroidMulticastLock({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('neosapien/native_bridge');

  final MethodChannel _channel;
  int _depth = 0;

  Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    _depth++;
    if (_depth == 1) {
      try {
        await _channel.invokeMethod<void>('acquireMulticastLock');
      } on MissingPluginException {
        _depth = 0;
      }
    }
  }

  Future<void> release() async {
    if (!Platform.isAndroid) return;
    if (_depth <= 0) return;
    _depth--;
    if (_depth == 0) {
      try {
        await _channel.invokeMethod<void>('releaseMulticastLock');
      } on MissingPluginException {
        // ignore
      }
    }
  }
}
