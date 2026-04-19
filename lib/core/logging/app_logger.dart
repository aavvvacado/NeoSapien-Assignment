import 'dart:developer' as dev;

class AppLogger {
  static void info(String message) {
    dev.log(message, name: 'NeoSapien', level: 800);
  }

  static void warn(String message) {
    dev.log(message, name: 'NeoSapien', level: 900);
  }

  static void error(String scope, Object error, StackTrace stackTrace) {
    dev.log(
      '[$scope] $error',
      name: 'NeoSapien',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
