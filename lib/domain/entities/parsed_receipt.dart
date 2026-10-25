/// Kết quả bóc tách hoá đơn từ text OCR.
class ParsedReceipt {
  const ParsedReceipt({
    required this.rawText,
    this.amount,
    this.date,
    this.merchant,
    this.confidence = 0,
    this.amountCandidates = const <double>[],
  });

  static const ParsedReceipt empty =
      ParsedReceipt(rawText: '', amountCandidates: <double>[]);

  final String rawText;

  /// Tổng tiền được suy luận (null nếu không tìm thấy).
  final double? amount;

  final DateTime? date;
  final String? merchant;

  /// Điểm tin cậy tổng hợp 0..1 (amount + date + merchant).
  final double confidence;

  /// Danh sách số tiền tìm được, giảm dần - dùng cho chip "chọn nhanh".
  final List<double> amountCandidates;

  bool get isEmpty => amount == null && date == null && merchant == null;
}
