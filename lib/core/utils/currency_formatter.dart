/// Các tiện ích định dạng / đọc số tiền (không phụ thuộc locale của hệ thống).
class CurrencyFormatter {
  const CurrencyFormatter._();

  /// 1500000 -> "1.500.000"
  static String thousands(num value) {
    final bool negative = value < 0;
    final String raw = value.abs().round().toString();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) buffer.write('.');
      buffer.write(raw[i]);
    }
    return '${negative ? '-' : ''}$buffer';
  }

  /// 1500000 -> "1.500.000 ₫"
  static String currency(num value) => '${thousands(value)} ₫';

  /// Rút gọn cho nhãn trục / badge: 1.500.000 -> "1,5 Tr"
  static String compact(num value) {
    final num abs = value.abs();
    if (abs >= 1000000000) return '${_trim(abs / 1000000000)} Tỷ';
    if (abs >= 1000000) return '${_trim(abs / 1000000)} Tr';
    if (abs >= 1000) return '${_trim(abs / 1000)} N';
    return thousands(value);
  }

  static String _trim(double value) {
    final String text = value.toStringAsFixed(value >= 100 ? 0 : 1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text.replaceAll('.', ',');
  }

  /// Đọc chuỗi người dùng nhập / chuỗi OCR thành số.
  /// Hỗ trợ cả "150.000", "150,000", "150 000", "150000", "12,5".
  static double? parseNumber(String? input) {
    if (input == null) return null;
    final String cleaned = input.replaceAll(RegExp(r'[^0-9.,]'), '').trim();
    if (cleaned.isEmpty) return null;

    final bool hasDot = cleaned.contains('.');
    final bool hasComma = cleaned.contains(',');

    if (hasDot && hasComma) {
      // Dấu phân cách xuất hiện sau cùng là dấu thập phân.
      final int lastDot = cleaned.lastIndexOf('.');
      final int lastComma = cleaned.lastIndexOf(',');
      final String decimalSep = lastDot > lastComma ? '.' : ',';
      final String thousandSep = decimalSep == '.' ? ',' : '.';
      return double.tryParse(
        cleaned.replaceAll(thousandSep, '').replaceAll(decimalSep, '.'),
      );
    }

    if (hasDot || hasComma) {
      final String sep = hasDot ? '.' : ',';
      final List<String> parts = cleaned.split(sep);
      final bool looksLikeGrouping = parts.length > 1 &&
          parts.skip(1).every((String part) => part.length == 3) &&
          parts.first.isNotEmpty;
      if (looksLikeGrouping) {
        return double.tryParse(parts.join());
      }
      return double.tryParse(cleaned.replaceAll(sep, '.'));
    }

    return double.tryParse(cleaned);
  }
}
