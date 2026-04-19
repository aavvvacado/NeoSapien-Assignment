import 'package:flutter_test/flutter_test.dart';
import 'package:neosapien_assignment/core/constants/app_constants.dart';
import 'package:neosapien_assignment/core/utils/short_code_generator.dart';

void main() {
  test('short code generator returns configured length', () {
    final generated = ShortCodeGenerator.generate();
    expect(generated.length, AppConstants.shortCodeLength);
  });
}
