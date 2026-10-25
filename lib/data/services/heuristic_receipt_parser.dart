import 'dart:math' as math;

import '../../core/utils/currency_formatter.dart';
import '../../domain/entities/parsed_receipt.dart';
import '../../domain/services/receipt_parser.dart';

/// Bộ bóc tách hoá đơn bằng heuristic thuần regex - chạy offline, không tốn chi phí cloud.
///
/// Chiến lược:
/// 1. Chuẩn hoá text OCR (bỏ dấu tiếng Việt để so khớp từ khoá bền vững hơn).
/// 2. Loại bỏ token ngày/giờ/số điện thoại khỏi dòng trước khi tìm số tiền.
/// 3. Chấm điểm từng dòng theo từ khoá tổng tiền + mệnh giá + vị trí, chọn điểm cao nhất.
/// 4. Tách ngày theo DD/MM/YYYY, YYYY-MM-DD, DDMMYYYY và tự sửa ngày tương lai.
/// 5. Suy luận tên cửa hàng từ những dòng đầu tiên không phải "nhiễu".
class HeuristicReceiptParser implements ReceiptParser {
  const HeuristicReceiptParser();

  // ---------------------------------------------------------------------------
  // Regex
  // ---------------------------------------------------------------------------

  /// Token số tiền: 150.000 | 150,000 | 150 000 | 150000 | 1.500.000 | 12,5
  static final RegExp _amountToken = RegExp(
    r'\d{1,3}(?:[.,\s]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?',
  );

  static final RegExp _dateLike =
      RegExp(r'\d{1,4}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{1,4}');
  static final RegExp _timeLike = RegExp(r'\b\d{1,2}\s*[:h]\s*\d{2}(?::\d{2})?\b');
  static final RegExp _phoneLike = RegExp(r'\b0\d{8,10}\b');
  static final RegExp _dmy = RegExp(r'(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2,4})');
  static final RegExp _ymd = RegExp(r'(\d{4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,2})');
  static final RegExp _compactDate = RegExp(r'\b(\d{2})(\d{2})(\d{4})\b');
  static final RegExp _currencyMark = RegExp(r'(₫|đ\b|vnd|vnđ|dong|đồng)', caseSensitive: false);
  static final RegExp _digitOnly = RegExp(r'^[\d.,\s]+$');

  // ---------------------------------------------------------------------------
  // Từ điển điểm
  // ---------------------------------------------------------------------------

  /// [trọng số, các biến thể không dấu]
  static const List<List<Object>> _totalKeywords = <List<Object>>[
    <Object>[130, <String>['grand total', 'tong cong', 'tong hoa don', 'total payment']],
    <Object>[115, <String>['tong thanh toan', 'tong tien thanh toan', 'tong tien', 'tong phai tra']],
    <Object>[100, <String>['thanh toan', 'phai thanh toan', 'phai tra', 'can tra', 'amount due', 'total due']],
    <Object>[92, <String>['total']],
    <Object>[85, <String>['thanh tien', 'so tien', 'tien hang']],
    <Object>[70, <String>['tien mat', 'cash', 'tien tra']],
    <Object>[55, <String>['tong']],
    <Object>[30, <String>['tam tinh', 'subtotal', 'cong tien hang']],
  ];

  /// Dòng chứa các từ khoá này bị loại (không phải tổng tiền thực trả).
  static const List<String> _negativeKeywords = <String>[
    'tien khach dua', 'khach dua', 'tien thua', 'tien thoi', 'tra lai',
    'change due', 'change', 'tien nhan', 'tien tra khach', 'giam gia',
    'chiet khau', 'discount', 'khuyen mai', 'voucher', 'coupon', 'diem thuong',
    'tich diem', 'no cu', 'cong no',
  ];

  /// Từ khoá giảm điểm nhẹ (thường là dòng phụ).
  static const Map<String, int> _softNegativeKeywords = <String, int>{
    'vat': -70,
    'thue': -60,
    'tax': -60,
    'so luong': -45,
    'sl:': -45,
    'qty': -45,
    'don gia': -45,
    'unit price': -45,
    'price': -30,
    'tien tip': -40,
  };

  static const List<String> _dateKeywords = <String>[
    'ngay', 'date', 'ngay in', 'thoi gian', 'time', 'ngay lap',
  ];

  /// Dòng nhiễu - không thể là tên cửa hàng.
  static const List<String> _merchantNoise = <String>[
    'hoa don', 'hoá đơn', 'receipt', 'invoice', 'bien lai', 'biên lai',
    'phieu', 'phiếu', 'ma so thue', 'mst', 'ma don', 'order', 'so hd',
    'tel', 'dien thoai', 'điện thoại', 'phone', 'hotline', 'fax', 'email',
    'dia chi', 'địa chỉ', 'address', 'website', 'www', 'http', 'facebook',
    'ngay', 'date', 'gio', 'time', 'pos', 'cashier', 'thu ngan', 'thu ngân',
    'nhan vien', 'nhân viên', 'khach hang', 'khách hàng', 'wifi', 'cam on',
    'cảm ơn', 'thank', 'xin chao', 'quy khach', 'khach quy',
  ];

  // ---------------------------------------------------------------------------
  // API
  // ---------------------------------------------------------------------------

  @override
  ParsedReceipt parse(String rawText) {
    final String normalized = rawText.replaceAll('\r', '');
    if (normalized.trim().isEmpty) return ParsedReceipt.empty;

    final List<String> lines = _splitLines(normalized);
    final DateTime? date = _extractDate(lines);
    final String? merchant = _extractMerchant(lines);
    final _AmountPick? pick = _extractTotal(lines);

    double confidence = 0;
    if (pick != null) {
      confidence += pick.keywordDriven ? 0.6 : 0.42;
    }
    if (date != null) confidence += 0.22;
    if (merchant != null) confidence += 0.18;

    return ParsedReceipt(
      rawText: rawText,
      amount: pick?.value,
      date: date,
      merchant: merchant,
      confidence: confidence.clamp(0, 1).toDouble(),
      amountCandidates: pick?.candidates ?? const <double>[],
    );
  }

  // ---------------------------------------------------------------------------
  // Số tiền
  // ---------------------------------------------------------------------------

  _AmountPick? _extractTotal(List<String> lines) {
    final List<double> allAmounts = <double>[];
    final Set<String> seen = <String>{};

    double? bestValue;
    int bestScore = -1 << 30;
    bool bestKeywordDriven = false;

    for (int index = 0; index < lines.length; index++) {
      final String rawLine = lines[index];
      final String flat = _deaccent(rawLine);
      final String scannable = rawLine
          .replaceAll(_dateLike, ' ')
          .replaceAll(_timeLike, ' ')
          .replaceAll(_phoneLike, ' ');

      final List<double> lineAmounts = _amountsIn(scannable);
      if (lineAmounts.isEmpty) continue;

      for (final double value in lineAmounts) {
        final String tag = value.toStringAsFixed(0);
        if (value > 0 && seen.add(tag)) allAmounts.add(value);
      }

      if (_negativeKeywords.any(flat.contains)) continue;

      int score = _keywordScore(flat) + _softNegativeScore(flat);
      final bool keywordDriven = score > 0;

      if (_currencyMark.hasMatch(rawLine)) score += 25;
      score += _magnitudeBonus(lineAmounts.reduce(math.max));
      if (lines.length > 1 && index >= (lines.length * 0.55)) score += 8;

      final double lineMax = lineAmounts.reduce(math.max);
      if (score > bestScore) {
        bestScore = score;
        bestValue = lineMax;
        bestKeywordDriven = keywordDriven;
      }
    }

    if (allAmounts.isEmpty) return null;

    allAmounts.sort((double a, double b) => b.compareTo(a));
    final List<double> candidates = allAmounts.take(4).toList();

    // Không có dòng nào mang từ khoá tổng tiền -> chọn số lớn nhất (trừ số vô lý).
    if (bestValue == null || bestScore <= 0) {
      final List<double> sane = allAmounts
          .where((double value) => value >= 1000 && value < 1e10)
          .toList();
      final double fallback = sane.isNotEmpty ? sane.first : allAmounts.first;
      return _AmountPick(
        value: fallback,
        candidates: candidates,
        keywordDriven: false,
      );
    }

    return _AmountPick(
      value: bestValue,
      candidates: candidates,
      keywordDriven: bestKeywordDriven,
    );
  }

  /// Lấy các số tiền hợp lệ trong một dòng (đã loại ngày/giờ/số điện thoại).
  List<double> _amountsIn(String line) {
    final String flat = _deaccent(line);
    final bool dateContext = _dateKeywords.any(flat.contains);
    final bool hasSeparatorOrMark =
        _currencyMark.hasMatch(line) || line.contains('.') || line.contains(',');

    final List<double> result = <double>[];
    for (final RegExpMatch match in _amountToken.allMatches(line)) {
      final String token = match.group(0)!;
      final double? value = CurrencyFormatter.parseNumber(token);
      if (value == null || value <= 0 || value >= 1e11) continue;

      final bool bare = !token.contains('.') && !token.contains(',') &&
          !token.contains(' ');
      // Bỏ số kiểu "2025" khi đứng cạnh ngữ cảnh ngày & không có dấu phân cách.
      if (bare && dateContext && value >= 1900 && value <= 2100) continue;
      // Bỏ chuỗi 8-10 chữ số thuần (thường là mã/số điện thoại).
      if (bare && token.length >= 8) continue;
      if (!hasSeparatorOrMark && token.length > 7) continue;

      result.add(value);
    }
    return result;
  }

  int _keywordScore(String flatLine) {
    int score = 0;
    for (final List<Object> entry in _totalKeywords) {
      final int weight = entry[0] as int;
      final List<String> variants = entry[1] as List<String>;
      for (final String variant in variants) {
        if (flatLine.contains(variant)) {
          score = math.max(score, weight);
          break;
        }
      }
    }
    return score;
  }

  int _softNegativeScore(String flatLine) {
    int score = 0;
    _softNegativeKeywords.forEach((String keyword, int delta) {
      if (flatLine.contains(keyword)) score += delta;
    });
    return score;
  }

  int _magnitudeBonus(double value) {
    if (value <= 0) return 0;
    return (math.log(value) / math.ln10 * 3).round().clamp(0, 26);
  }

  // ---------------------------------------------------------------------------
  // Ngày
  // ---------------------------------------------------------------------------

  DateTime? _extractDate(List<String> lines) {
    DateTime? firstFound;
    DateTime? keywordContext;

    for (final String line in lines) {
      final DateTime? parsed = _dateIn(line);
      if (parsed == null) continue;
      firstFound ??= parsed;
      final String flat = _deaccent(line);
      if (_dateKeywords.any(flat.contains)) {
        keywordContext ??= parsed;
      }
    }

    final DateTime? chosen = keywordContext ?? firstFound;
    if (chosen == null) return null;
    return _repairFutureDate(chosen);
  }

  DateTime? _dateIn(String line) {
    final RegExpMatch? ymd = _ymd.firstMatch(line);
    if (ymd != null) {
      final DateTime? value = _build(
        int.parse(ymd.group(1)!),
        int.parse(ymd.group(2)!),
        int.parse(ymd.group(3)!),
      );
      if (value != null) return value;
    }

    final RegExpMatch? dmy = _dmy.firstMatch(line);
    if (dmy != null) {
      final DateTime? value = _build(
        int.parse(dmy.group(3)!),
        int.parse(dmy.group(2)!),
        int.parse(dmy.group(1)!),
      );
      if (value != null) return value;
    }

    final RegExpMatch? compact = _compactDate.firstMatch(line);
    if (compact != null) {
      return _build(
        int.parse(compact.group(3)!),
        int.parse(compact.group(2)!),
        int.parse(compact.group(1)!),
      );
    }

    return null;
  }

  DateTime? _build(int year, int month, int day) {
    final int normalizedYear = year < 100 ? 2000 + year : year;
    if (normalizedYear < 2000 || normalizedYear > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    try {
      final DateTime value = DateTime(normalizedYear, month, day);
      if (value.month != month || value.day != day) return null;
      return value;
    } on ArgumentError {
      return null;
    }
  }

  /// Hoá đơn không thể ở tương lai: nếu ngày vượt hiện tại, thử đảo ngày/tháng
  /// (trường hợp hoá đơn ghi theo MM/DD).
  DateTime _repairFutureDate(DateTime value) {
    final DateTime now = DateTime.now();
    final DateTime limit = now.add(const Duration(days: 1));
    if (!value.isAfter(limit)) return value;

    final DateTime swapped = DateTime(value.year, value.day, value.month);
    final bool swappedValid =
        swapped.month == value.day && swapped.day == value.month;
    if (swappedValid && !swapped.isAfter(limit)) return swapped;
    return value;
  }

  // ---------------------------------------------------------------------------
  // Tên cửa hàng
  // ---------------------------------------------------------------------------

  String? _extractMerchant(List<String> lines) {
    final int primaryLimit = math.min(lines.length, 6);
    for (int index = 0; index < primaryLimit; index++) {
      final String? candidate = _cleanMerchant(lines[index]);
      if (candidate != null) return candidate;
    }
    for (int index = primaryLimit; index < lines.length; index++) {
      final String? candidate = _cleanMerchant(lines[index]);
      if (candidate != null) return candidate;
    }
    return null;
  }

  String? _cleanMerchant(String rawLine) {
    String line = rawLine.trim();
    if (line.length < 3 || line.length > 60) return null;

    final String flat = _deaccent(line);
    if (_merchantNoise.any(flat.contains)) return null;

    final int digits = RegExp(r'\d').allMatches(line).length;
    if (digits / line.length > 0.35) return null;

    final int letters = RegExp(r'[A-Za-zÀ-ỹ]').allMatches(line).length;
    if (letters < 3) return null;

    line = line
        .replaceAll(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N})\]]+$', unicode: true), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (line.length < 3) return null;

    // Toàn chữ HOA -> chuyển về Title Case cho dễ đọc.
    final bool isUpper = line == line.toUpperCase() && RegExp(r'[A-ZÀ-Ỹ]').hasMatch(line);
    return isUpper ? _toTitleCase(line) : line;
  }

  String _toTitleCase(String value) {
    return value
        .split(' ')
        .map(
          (String word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  // ---------------------------------------------------------------------------
  // Tiện ích
  // ---------------------------------------------------------------------------

  List<String> _splitLines(String text) {
    return text
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
  }

  static const Map<String, String> _accentMap = <String, String>{
    'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
    'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
    'đ': 'd',
  };

  /// Bỏ dấu tiếng Việt để so khớp từ khoá ổn định trước sai lệch của OCR.
  static String _deaccent(String input) {
    final String lower = input.toLowerCase();
    final StringBuffer buffer = StringBuffer();
    for (final int rune in lower.runes) {
      final String char = String.fromCharCode(rune);
      buffer.write(_accentMap[char] ?? char);
    }
    return buffer.toString();
  }

  /// Có phải dòng chỉ chứa số/ký tự phân cách (dùng để test nhanh).
  static bool isNumericLine(String line) => _digitOnly.hasMatch(line.trim());
}

class _AmountPick {
  const _AmountPick({
    required this.value,
    required this.candidates,
    required this.keywordDriven,
  });

  final double value;
  final List<double> candidates;

  /// True khi tìm được nhờ từ khoá "tổng ...", tin cậy hơn fallback theo mệnh giá.
  final bool keywordDriven;
}
