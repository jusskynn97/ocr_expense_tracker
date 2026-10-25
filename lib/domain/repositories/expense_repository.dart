import '../entities/expense.dart';

/// Hợp đồng truy cập dữ liệu chi tiêu (được hiện thực ở tầng data).
abstract interface class ExpenseRepository {
  Future<List<Expense>> getExpenses({DateTime? from, DateTime? to});

  Future<Expense?> getExpense(int id);

  /// Trả về id vừa tạo.
  Future<int> createExpense(Expense expense);

  Future<void> updateExpense(Expense expense);

  Future<void> deleteExpense(int id);

  /// Xoá toàn bộ dữ liệu (dùng cho tính năng dọn dẹp).
  Future<void> deleteAll();
}
