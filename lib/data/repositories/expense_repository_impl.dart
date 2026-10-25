import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';
import '../datasources/expense_local_data_source.dart';

/// Hiện thực [ExpenseRepository] trên SQLite cục bộ.
class ExpenseRepositoryImpl implements ExpenseRepository {
  const ExpenseRepositoryImpl(this._localDataSource);

  final ExpenseLocalDataSource _localDataSource;

  @override
  Future<List<Expense>> getExpenses({DateTime? from, DateTime? to}) {
    return _localDataSource.fetchExpenses(from: from, to: to);
  }

  @override
  Future<Expense?> getExpense(int id) => _localDataSource.findById(id);

  @override
  Future<int> createExpense(Expense expense) => _localDataSource.insert(expense);

  @override
  Future<void> updateExpense(Expense expense) => _localDataSource.update(expense);

  @override
  Future<void> deleteExpense(int id) => _localDataSource.delete(id);

  @override
  Future<void> deleteAll() => _localDataSource.deleteAll();
}
