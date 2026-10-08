class IsbnValidationException implements Exception {
  const IsbnValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class Isbn {
  static String? normalizeOptional(String input) {
    final compact = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (compact.isEmpty) return null;
    if (compact.length == 10) {
      if (!_isValidIsbn10(compact)) {
        throw const IsbnValidationException(
          'Enter a valid ISBN-10 or ISBN-13.',
        );
      }
      return _isbn10To13(compact);
    }
    if (compact.length == 13 && _isValidIsbn13(compact)) return compact;
    throw const IsbnValidationException('Enter a valid ISBN-10 or ISBN-13.');
  }

  static bool _isValidIsbn10(String value) {
    if (!RegExp(r'^\d{9}[\dX]$').hasMatch(value)) return false;
    var sum = 0;
    for (var index = 0; index < 10; index += 1) {
      final digit = value[index] == 'X' ? 10 : int.parse(value[index]);
      sum += digit * (10 - index);
    }
    return sum % 11 == 0;
  }

  static bool _isValidIsbn13(String value) {
    if (!RegExp(r'^\d{13}$').hasMatch(value)) return false;
    var sum = 0;
    for (var index = 0; index < 13; index += 1) {
      final digit = int.parse(value[index]);
      sum += digit * (index.isEven ? 1 : 3);
    }
    return sum % 10 == 0;
  }

  static String _isbn10To13(String value) {
    final prefix = '978${value.substring(0, 9)}';
    var sum = 0;
    for (var index = 0; index < prefix.length; index += 1) {
      sum += int.parse(prefix[index]) * (index.isEven ? 1 : 3);
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return '$prefix$checkDigit';
  }
}
