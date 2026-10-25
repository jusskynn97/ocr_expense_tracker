import '../entities/expense.dart';
import '../repositories/expense_repository.dart';
import 'create_expense.dart';

class UpdateExpenseUseCase {
  const UpdateExpenseUseCase(this._repository);

  final ExpenseRepository _repository;

  Future<Expense> call(Expense expense) async {
    if (expense.id == null) {
      throw const InvalidExpenseException('Không tìm thấy chi tiêu cần cập nhật.');
    }
    if (expense.amount <= 0) {
      throw const InvalidExpenseException('Số tiền phải lớn hơn 0.');
    }
    final String merchant = expense.merchant.trim();
    final Expense sanitized = expense.copyWith(
      merchant: merchant.isEmpty ? 'Không xác định' : merchant,
    );
    await _repository.updateExpense(sanitized);
    return sanitized;
  }
}
