import 'expense.dart';
import 'expense_category.dart';

/// Một nhát cắt của biểu đồ tròn.
class CategorySlice {
  const CategorySlice({
    required this.category,
    required this.amount,
    required this.share,
    required this.count,
  });

  final ExpenseCategory category;
  final double amount;

  /// Tỉ lệ 0..1 trên tổng chi tiêu.
  final double share;
  final int count;
}

/// Tổng hợp chi tiêu theo khoảng thời gian.
class SpendingSummary {
  const SpendingSummary({
    required this.total,
    required this.slices,
    required this.count,
    required this.average,
    required this.topCategory,
  });

  static const SpendingSummary empty = SpendingSummary(
    total: 0,
    slices: <CategorySlice>[],
    count: 0,
    average: 0,
    topCategory: null,
  );

  final double total;
  final List<CategorySlice> slices;
  final int count;
  final double average;
  final ExpenseCategory? topCategory;
}

/// Tổng chi tiêu của một ngày (dùng cho bar chart tuần).
class DailyTotal {
  const DailyTotal({required this.date, required this.amount});

  final DateTime date;
  final double amount;
}

/// Bộ tính toán thuần Dart - tách khỏi tầng dữ liệu để dễ test.
class SpendingCalculator {
  const SpendingCalculator._();

  static SpendingSummary summarize(List<Expense> expenses) {
    if (expenses.isEmpty) return SpendingSummary.empty;

    final Map<ExpenseCategory, double> totals = <ExpenseCategory, double>{};
    final Map<ExpenseCategory, int> counts = <ExpenseCategory, int>{};
    double total = 0;

    for (final Expense expense in expenses) {
      total += expense.amount;
      totals[expense.category] = (totals[expense.category] ?? 0) + expense.amount;
      counts[expense.category] = (counts[expense.category] ?? 0) + 1;
    }

    final List<CategorySlice> slices = totals.entries
        .map(
          (MapEntry<ExpenseCategory, double> entry) => CategorySlice(
            category: entry.key,
            amount: entry.value,
            share: total == 0 ? 0 : entry.value / total,
            count: counts[entry.key] ?? 0,
          ),
        )
        .toList()
      ..sort((CategorySlice a, CategorySlice b) => b.amount.compareTo(a.amount));

    return SpendingSummary(
      total: total,
      slices: slices,
      count: expenses.length,
      average: total / expenses.length,
      topCategory: slices.isEmpty ? null : slices.first.category,
    );
  }

  static SpendingSummary summarizeInRange(List<Expense> expenses, DateTime from, DateTime to) {
    return summarize(
      expenses
          .where(
            (Expense expense) =>
                !expense.date.isBefore(from) && !expense.date.isAfter(to),
          )
          .toList(),
    );
  }

  /// Trả về đúng 7 phần tử, từ `startDay` đến `startDay + 6 ngày`.
  static List<DailyTotal> dailyTotals(List<Expense> expenses, DateTime startDay) {
    final DateTime start = DateTime(startDay.year, startDay.month, startDay.day);
    final List<DailyTotal> result = List<DailyTotal>.generate(
      7,
      (int index) => DailyTotal(date: start.add(Duration(days: index)), amount: 0),
    );

    for (final Expense expense in expenses) {
      final int diff = DateTime(expense.date.year, expense.date.month, expense.date.day)
          .difference(start)
          .inDays;
      if (diff < 0 || diff > 6) continue;
      result[diff] = DailyTotal(
        date: result[diff].date,
        amount: result[diff].amount + expense.amount,
      );
    }
    return result;
  }

  static List<Expense> sortByDateDesc(List<Expense> expenses) {
    final List<Expense> sorted = List<Expense>.of(expenses);
    sorted.sort((Expense a, Expense b) {
      final int byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return (b.id ?? 0).compareTo(a.id ?? 0);
    });
    return sorted;
  }
}
