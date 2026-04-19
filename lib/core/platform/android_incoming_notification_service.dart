import 'dart:io';

import 'package:flutter/services.dart';

class AndroidIncomingNotificationService {
  static const MethodChannel _channel =
      MethodChannel('neosapien/native_bridge');

  /// Android 13+: asks for [POST_NOTIFICATIONS] so heads-up alerts can appear.
  Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestPostNotificationsPermission');
    } catch (_) {}
  }

  Future<void> showIncomingTransferNotification({
    required String transferId,
    required String senderPreview,
    required int fileCount,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('showIncomingTransferNotification', {
      'transferId': transferId,
      'senderPreview': senderPreview,
      'fileCount': fileCount,
    });
  }

  Future<String?> consumeInitialTransferId() async {
    if (!Platform.isAndroid) return null;
    final id = await _channel.invokeMethod<String?>('consumeInitialTransferId');
    if (id == null || id.trim().isEmpty) return null;
    return id;
  }

  /// Lightweight heads-up (same channel stack as incoming; separate id slot).
  /// Tap notification to open the saved file (no generic “saved” text only).
  Future<void> showDownloadSavedNotification({
    required String fileName,
    required String openUriOrPath,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('showDownloadSavedNotification', {
        'fileName': fileName,
        'openUriOrPath': openUriOrPath,
      });
    } catch (_) {}
  }

  Future<void> showHeadsUpStatus({
    required String title,
    required String body,
    int notificationId = 7801,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('showHeadsUpStatus', {
        'title': title,
        'body': body,
        'notificationId': notificationId,
      });
    } catch (_) {
      // Ignore if older host without handler.
    }
  }
}
