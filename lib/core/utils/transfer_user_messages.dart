import 'app_error_mapper.dart';

/// Maps technical exceptions and failure strings to short, user-facing copy.
abstract final class TransferUserMessages {
  const TransferUserMessages._();

  /// Prefer for [Failure.message] or [Object.toString] from catch blocks.
  static String describe(Object? error) {
    if (error == null) return 'Something went wrong. Please try again.';
    final s = error.toString();
    final lower = s.toLowerCase();

    // Use AppErrorMapper as the primary sanitizer for known network/logic patterns
    final mapped = AppErrorMapper.map(error);
    if (!mapped.contains('unexpected network error')) {
      return mapped;
    }

    if (lower.contains('integrity check failed') ||
        lower.contains('hash_mismatch')) {
      return 'Downloaded file did not match the sender checksum. Try again or ask the sender to resend.';
    }
    if (lower.contains('lan_delivery_not_available')) {
      return 'This transfer was delivered over nearby Wi‑Fi, but the local copy is no longer on this device. Ask the sender to resend.';
    }
    if (lower.contains('storageexception') ||
        lower.contains('not_found') ||
        lower.contains('"404"') ||
        lower.contains('404')) {
      return 'Could not load the file from storage. It may be missing.';
    }
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('not authorized')) {
      return 'Access was denied. Check your session status.';
    }
    if (lower.contains('401') || lower.contains('jwt')) {
      return 'Your session is not valid. Restart the app to reconnect.';
    }
    if (lower.contains('invalid_recipient_code')) {
      return 'That recipient code is not registered.';
    }
    if (lower.contains('self_send_not_allowed')) {
      return 'Same device sending is not authorized.';
    }

    // Final fallback: Use the mapped professional generic message instead of raw technical strings
    return mapped;
  }

  static String describeFailureMessage(String message) => describe(message);
}
