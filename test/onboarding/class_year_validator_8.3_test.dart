import 'package:flutter_test/flutter_test.dart';
import 'package:dogpack/onboarding/class_year_validator.dart';

void main() {
  group('validateClassYear Tests', () {
    test('should return null for all valid lower-case class years', () {
      for (final year in classYearValues) {
        expect(validateClassYear(year), isNull);
      }
    });

    test('should return error message for invalid, capitalized, or null inputs', () {
      expect(validateClassYear('Graduate'), 'Choose a class year.');
      expect(validateClassYear('unknown'), 'Choose a class year.');
      expect(validateClassYear(null), 'Choose a class year.');
      expect(validateClassYear(''), 'Choose a class year.');
    });
  });
}