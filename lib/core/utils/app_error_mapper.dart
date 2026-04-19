import 'dart:io';
import 'package:http/http.dart';

class AppErrorMapper {
  static String map(Object error) {
    if (error is SocketException) {
      if (error.message.contains('Failed host lookup')) {
        return 'Internet connection lost. Please check your network.';
      }
      return 'Network error. Please try again later.';
    }
    
    if (error is ClientException) {
      return 'Connection interupted. Reconnecting...';
    }

    if (error is HttpException) {
      return 'Server communication failed. Please try again.';
    }

    final str = error.toString().toLowerCase();
    if (str.contains('socketexception') || str.contains('failed host lookup')) {
      return 'Internet connection lost. Please check your network.';
    }
    
    if (str.contains('clientexception')) {
      return 'Network request failed. Please check your connection.';
    }

    if (str.contains('self_send_not_allowed')) {
      return 'Same device sending is not authorized. Please send to another device.';
    }

    if (str.contains('aborted') || str.contains('cancelled')) {
      return 'Transfer interrupted. Tap Resume to continue.';
    }

    if (str.contains('invalid_recipient_code')) {
      return 'Invalid recipient code. Please check and try again.';
    }

    if (str.contains('broken pipe') || str.contains('connection closed')) {
      return 'Network interrupted. Retrying...';
    }

    if (str.contains('not enough device storage')) {
      // Keep the specific message from StateError if it exists, or provide generic
      return error.toString().replaceAll('StateError: ', '').replaceAll('Exception: ', '');
    }

    // Default to a professional generic message if we don't recognize the specific error
    return 'An unexpected network error occurred. Please tap Resume to retry.';
  }
}
