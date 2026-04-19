import 'dart:math';

import 'package:neosapien_assignment/core/constants/app_constants.dart';

class ShortCodeGenerator {
  static final Random _random = Random.secure();

  static String generate() {
    final buffer = StringBuffer();
    // Using 8 chars as requested to maintain stability, but ensuring high entropy
    for (int i = 0; i < AppConstants.shortCodeLength; i++) {
      final idx = _random.nextInt(AppConstants.shortCodeAlphabet.length);
      buffer.write(AppConstants.shortCodeAlphabet[idx]);
    }
    return buffer.toString();
  }
}
