import '../entities/parsed_receipt.dart';

/// Bộ máy heuristic (regex) bóc tách tổng tiền, ngày, tên cửa hàng từ text OCR.
abstract interface class ReceiptParser {
  ParsedReceipt parse(String rawText);
}
