import 'package:flutter/foundation.dart';

import '../../core/utils/date_time_formatter.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/spending_summary.dart';
import '../../domain/usecases/create_expense.dart';
import '../../domain/usecases/delete_expense.dart';
import '../../domain/usecases/get_expenses.dart';
import '../../domain/usecases/update_expense.dart';

/// Một nhóm chi tiêu theo ngày (view-model cho danh sách).
class ExpenseDayGroup {
  const ExpenseDayGroup({
    required this.day,
    required this.expenses,
    required this.total,
  });

  final DateTime day;
  final List<Expense> expenses;
  final double total;
}

/// State toàn cục cho danh sách chi tiêu + các số liệu tổng hợp.
class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider({
    required GetExpensesUseCase getExpenses,
    required CreateExpenseUseCase createExpense,
    required UpdateExpenseUseCase updateExpense,
    required DeleteExpenseUseCase deleteExpense,
  })  : _getExpenses = getExpenses,
        _createExpense = createExpense,
        _updateExpense = updateExpense,
        _deleteExpense = deleteExpense;

  final GetExpensesUseCase _getExpenses;
  final CreateExpenseUseCase _createExpense;
  final UpdateExpenseUseCase _updateExpense;
  final DeleteExpenseUseCase _deleteExpense;

  List<Expense> _expenses = const <Expense>[];
  bool _isLoading = true;
  String? _errorMessage;
  bool _disposed = false;

  List<Expense> get expenses => _expenses;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => !_isLoading && _expenses.isEmpty;

  // ---------------------------------------------------------------------------
  // Số liệu tổng hợp
  // ---------------------------------------------------------------------------

  SpendingSummary get allTimeSummary => SpendingCalculator.summarize(_expenses);

  SpendingSummary get monthSummary =>
      SpendingCalculator.summarizeInRange(_expenses, _monthStart, _monthEnd);

  SpendingSummary get previousMonthSummary => SpendingCalculator.summarizeInRange(
        _expenses,
        DateTime(_monthStart.year, _monthStart.month - 1, 1),
        DateTime(_monthStart.year, _monthStart.month, 0, 23, 59, 59),
      );

  SpendingSummary get weekSummary => SpendingCalculator.summarizeInRange(
        _expenses,
        _weekStart,
        _weekEnd,
      );

  List<DailyTotal> get currentWeekTotals =>
      SpendingCalculator.dailyTotals(_expenses, _weekStart);

  /// % tăng/giảm so với tháng trước (null nếu tháng trước không có dữ liệu).
  double? get monthChangeRatio {
    final double current = monthSummary.total;
    final double previous = previousMonthSummary.total;
    if (previous <= 0) return null;
    return (current - previous) / previous;
  }

  double get todayTotal {
    final DateTime now = DateTime.now();
    return _expenses
        .where((Expense expense) => AppDateFormatter.isSameDay(expense.date, now))
        .fold(0, (double sum, Expense expense) => sum + expense.amount);
  }

  List<Expense> get recentExpenses => _expenses.take(30).toList();

  /// Danh sách đã nhóm theo ngày, giữ nguyên thứ tự mới nhất trước.
  List<ExpenseDayGroup> get groupedByDay {
    final List<ExpenseDayGroup> groups = <ExpenseDayGroup>[];
    for (final Expense expense in _expenses) {
      final DateTime day = AppDateFormatter.startOfDay(expense.date);
      if (groups.isNotEmpty && AppDateFormatter.isSameDay(groups.last.day, day)) {
        final ExpenseDayGroup last = groups.removeLast();
        groups.add(
          ExpenseDayGroup(
            day: last.day,
            expenses: <Expense>[...last.expenses, expense],
            total: last.total + expense.amount,
          ),
        );
      } else {
        groups.add(
          ExpenseDayGroup(
            day: day,
            expenses: <Expense>[expense],
            total: expense.amount,
          ),
        );
      }
    }
    return groups;
  }

  SpendingSummary summaryForMonth(DateTime month) => SpendingCalculator.summarizeInRange(
        _expenses,
        AppDateFormatter.startOfMonth(month),
        AppDateFormatter.endOfMonth(month),
      );

  // ---------------------------------------------------------------------------
  // Hành động
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();
    try {
      _expenses = await _getExpenses();
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Không đọc được dữ liệu: $error';
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<Expense> add(Expense expense) async {
    final Expense created = await _createExpense(expense);
    await load();
    return created;
  }

  Future<void> save(Expense expense) async {
    await _updateExpense(expense);
    await load();
  }

  Future<void> remove(int id) async {
    await _deleteExpense(id);
    await load();
  }

  // ---------------------------------------------------------------------------
  // Nội bộ
  // ---------------------------------------------------------------------------

  DateTime get _monthStart => AppDateFormatter.startOfMonth(DateTime.now());

  DateTime get _monthEnd => AppDateFormatter.endOfMonth(DateTime.now());

  DateTime get _weekStart => AppDateFormatter.startOfWeek(DateTime.now());

  DateTime get _weekEnd =>
      AppDateFormatter.endOfDay(_weekStart.add(const Duration(days: 6)));

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
