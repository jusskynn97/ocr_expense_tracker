import '../entities/expense_category.dart';
import '../entities/parsed_receipt.dart';
import '../services/category_classifier.dart';
import '../services/receipt_parser.dart';
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

/// Pipeline: ảnh -> ML Kit OCR -> heuristic regex -> dữ liệu có cấu trúc.
class ScanReceiptUseCase {
  const ScanReceiptUseCase(this._recognizer, this._parser);

  final TextRecognizerService _recognizer;
  final ReceiptParser _parser;

  Future<ScanResult> call(String imagePath) async {
    final String rawText = await _recognizer.extractText(imagePath);
    final ParsedReceipt receipt = _parser.parse(rawText);
    return ScanResult(
      receipt: receipt,
      suggestedCategory: CategoryClassifier.classify(
        receipt.merchant,
        rawText,
      ),
    );
  }
}
