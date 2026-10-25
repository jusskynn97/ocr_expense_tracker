/// Nhóm chi tiêu cố định của ứng dụng (domain thuần Dart, không phụ thuộc Flutter).
enum ExpenseCategory {
  food('food', 'Ăn uống'),
  study('study', 'Học tập'),
  travel('travel', 'Di chuyển'),
  gear('gear', 'Thiết bị'),
  entertainment('entertainment', 'Giải trí');

  const ExpenseCategory(this.id, this.label);

  /// Khoá lưu trong database.
  final String id;

  /// Nhãn hiển thị.
  final String label;

  static ExpenseCategory fromId(String? id) {
    return ExpenseCategory.values.firstWhere(
      (ExpenseCategory value) => value.id == id,
      orElse: () => ExpenseCategory.food,
    );
  }
}
