import 'package:neosapien_assignment/core/constants/app_constants.dart';

/// Client-side rules for **recipient** codes before hitting Supabase.
/// Issued codes are length [AppConstants.shortCodeLength]; the brief allows 6–8 for human handles.
class ShortCodeInputValidator {
  ShortCodeInputValidator._();

  static const int minRecipientLength = 6;
  static const int maxRecipientLength = 8;

  static String normalize(String raw) => raw.trim().toUpperCase();

  /// Every character must be in [AppConstants.shortCodeAlphabet] (no I/O/0/1).
  static bool syntaxValidForLookup(String normalized) {
    if (normalized.isEmpty) return false;
    if (normalized.length < minRecipientLength ||
        normalized.length > maxRecipientLength) {
      return false;
    }
    for (var i = 0; i < normalized.length; i++) {
      if (!AppConstants.shortCodeAlphabet.contains(normalized[i])) {
        return false;
      }
    }
    return true;
  }

  static String syntaxInvalidUserMessage() =>
      'Enter a code of $minRecipientLength–$maxRecipientLength characters using '
      'only A–Z (except I and O) and digits 2–9. This code is not in a valid format.';
}
