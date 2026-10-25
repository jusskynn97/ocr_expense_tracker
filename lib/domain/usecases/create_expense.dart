import '../entities/expense.dart';
import '../repositories/expense_repository.dart';

class CreateExpenseUseCase {
  const CreateExpenseUseCase(this._repository);

  final ExpenseRepository _repository;

  Future<Expense> call(Expense expense) async {
    if (expense.amount <= 0) {
      throw const InvalidExpenseException('Số tiền phải lớn hơn 0.');
    }
    final String merchant = expense.merchant.trim();
    final Expense sanitized = expense.copyWith(
      merchant: merchant.isEmpty ? 'Không xác định' : merchant,
      createdAt: expense.createdAt ?? DateTime.now(),
    );
    final int id = await _repository.createExpense(sanitized);
    return sanitized.copyWith(id: id);
  }
}

class InvalidExpenseException implements Exception {
  const InvalidExpenseException(this.message);

  final String message;

  @override
  String toString() => message;
}
