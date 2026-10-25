import 'expense_category.dart';

/// Thực thể chi tiêu - trung tâm của domain.
class Expense {
  const Expense({
    this.id,
    required this.amount,
    required this.merchant,
    required this.date,
    required this.category,
    this.note,
    this.receiptPath,
    this.rawText,
    this.createdAt,
  });

  final int? id;
  final double amount;
  final String merchant;
  final DateTime date;
  final ExpenseCategory category;
  final String? note;

  /// Đường dẫn thumbnail hoá đơn trong thư mục ứng dụng (đã cache).
  final String? receiptPath;

  /// Text thô từ OCR, giữ lại để đối chiếu về sau.
  final String? rawText;

  final DateTime? createdAt;

  Expense copyWith({
    int? id,
    double? amount,
    String? merchant,
    DateTime? date,
    ExpenseCategory? category,
    String? note,
    String? receiptPath,
    String? rawText,
    DateTime? createdAt,
  }) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      merchant: merchant ?? this.merchant,
      date: date ?? this.date,
      category: category ?? this.category,
      note: note ?? this.note,
      receiptPath: receiptPath ?? this.receiptPath,
      rawText: rawText ?? this.rawText,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
