import '../entities/expense.dart';
import '../entities/spending_summary.dart';
import '../repositories/expense_repository.dart';

class GetExpensesUseCase {
  const GetExpensesUseCase(this._repository);

  final ExpenseRepository _repository;

  /// Lấy danh sách chi tiêu (mặc định toàn bộ), sắp xếp mới nhất trước.
  Future<List<Expense>> call({DateTime? from, DateTime? to}) async {
    final List<Expense> expenses =
        await _repository.getExpenses(from: from, to: to);
    return SpendingCalculator.sortByDateDesc(expenses);
  }
}
