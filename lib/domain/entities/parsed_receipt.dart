/// Kết quả bóc tách hoá đơn từ text OCR.
class ParsedReceipt {
  const ParsedReceipt({
    required this.rawText,
    this.amount,
    this.date,
    this.merchant,
    this.confidence = 0,
    this.amountCandidates = const <double>[],
    this.dateCandidates = const <DateTime>[],
    this.merchantCandidates = const <String>[],
    this.refinedByModel = false,
  });

  static const ParsedReceipt empty = ParsedReceipt(rawText: '');

  final String rawText;

  /// Tổng tiền được suy luận (null nếu không tìm thấy).
  final double? amount;

  final DateTime? date;
  final String? merchant;

  /// Điểm tin cậy tổng hợp 0..1 (amount + date + merchant).
  final double confidence;

  /// Danh sách số tiền tìm được, giảm dần - dùng cho chip "chọn nhanh".
  final List<double> amountCandidates;

  /// Các cách hiểu ngày khác nhau bóc được từ hoá đơn (đã khử trùng, tối đa 4).
  final List<DateTime> dateCandidates;

  /// Các dòng có thể là tên cửa hàng, theo thứ tự ưu tiên giảm dần.
  final List<String> merchantCandidates;

  /// True khi model ngôn ngữ nhỏ on-device đã đối chiếu/tinh chỉnh kết quả này.
  ///
  /// Dùng để UI báo cho người dùng biết vì sao điểm tin cậy thay đổi.
  final bool refinedByModel;

  bool get isEmpty => amount == null && date == null && merchant == null;

  /// Bản sao có ghi đè một phần trường. Truyền `null` nghĩa là giữ nguyên.
  ParsedReceipt copyWith({
    String? rawText,
    double? amount,
    DateTime? date,
    String? merchant,
    double? confidence,
    List<double>? amountCandidates,
    List<DateTime>? dateCandidates,
    List<String>? merchantCandidates,
    bool? refinedByModel,
  }) {
    return ParsedReceipt(
      rawText: rawText ?? this.rawText,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      merchant: merchant ?? this.merchant,
      confidence: confidence ?? this.confidence,
      amountCandidates: amountCandidates ?? this.amountCandidates,
      dateCandidates: dateCandidates ?? this.dateCandidates,
      merchantCandidates: merchantCandidates ?? this.merchantCandidates,
      refinedByModel: refinedByModel ?? this.refinedByModel,
    );
  }
}
