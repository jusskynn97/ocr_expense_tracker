import '../entities/expense_category.dart';
import '../entities/parsed_receipt.dart';
import '../services/category_classifier.dart';
import '../services/receipt_parser.dart';
import '../services/receipt_understander.dart';
import '../services/text_recognizer_service.dart';

/// Kết quả một phiên quét: dữ liệu bóc tách + gợi ý nhóm chi tiêu.
class ScanResult {
  const ScanResult({required this.receipt, required this.suggestedCategory});

  final ParsedReceipt receipt;
  final ExpenseCategory suggestedCategory;

  static const ScanResult empty = ScanResult(
    receipt: ParsedReceipt.empty,
    suggestedCategory: ExpenseCategory.food,
  );
}

/// Pipeline: ảnh -> ML Kit OCR -> heuristic regex -> (tuỳ chọn) SLM tinh chỉnh.
///
/// Hybrid: regex luôn chạy và cho kết quả ngay; model ngôn ngữ nhỏ on-device
/// chỉ chạy tiếp khi đã sẵn sàng, để đối chiếu lại các trường mà regex dễ sai.
class ScanReceiptUseCase {
  const ScanReceiptUseCase(
    this._recognizer,
    this._parser, [
    this._understander,
  ]);

  final TextRecognizerService _recognizer;
  final ReceiptParser _parser;
  final ReceiptUnderstander? _understander;

  Future<ScanResult> call(String imagePath) async {
    final String rawText = await _recognizer.extractText(imagePath);
    final ParsedReceipt baseline = _parser.parse(rawText);
    return ScanResult(
      receipt: await _refine(rawText, baseline),
      suggestedCategory: CategoryClassifier.classify(
        baseline.merchant,
        rawText,
      ),
    );
  }

  /// Chạy lại riêng bước tinh chỉnh (khi người dùng vừa bật trợ lý AI).
  Future<ScanResult> refineOnly(ScanResult current) async {
    if (current.receipt.rawText.trim().isEmpty) return current;
    return ScanResult(
      receipt: await _refine(current.receipt.rawText, current.receipt),
      suggestedCategory: current.suggestedCategory,
    );
  }

  Future<ParsedReceipt> _refine(
    String rawText,
    ParsedReceipt baseline,
  ) async {
    final ReceiptUnderstander? understander = _understander;
    if (understander == null || !understander.isReady) return baseline;
    return understander.refine(rawText: rawText, baseline: baseline);
  }
}
