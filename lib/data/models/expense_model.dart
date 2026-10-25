import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_category.dart';

/// Ánh xạ giữa thực thể [Expense] và bảng `expenses` của SQLite.
class ExpenseModel extends Expense {
  const ExpenseModel({
    super.id,
    required super.amount,
    required super.merchant,
    required super.date,
    required super.category,
    super.note,
    super.receiptPath,
    super.rawText,
    super.createdAt,
  });

  static const String table = 'expenses';
  static const String columnId = 'id';
  static const String columnAmount = 'amount';
  static const String columnMerchant = 'merchant';
  static const String columnCategory = 'category';
  static const String columnDate = 'date';
  static const String columnNote = 'note';
  static const String columnReceiptPath = 'receipt_path';
  static const String columnRawText = 'raw_text';
  static const String columnCreatedAt = 'created_at';

  factory ExpenseModel.fromEntity(Expense expense) {
    return ExpenseModel(
      id: expense.id,
      amount: expense.amount,
      merchant: expense.merchant,
      date: expense.date,
      category: expense.category,
      note: expense.note,
      receiptPath: expense.receiptPath,
      rawText: expense.rawText,
      createdAt: expense.createdAt,
    );
  }

  factory ExpenseModel.fromMap(Map<String, Object?> map) {
    return ExpenseModel(
      id: map[columnId] as int?,
      amount: (map[columnAmount] as num).toDouble(),
      merchant: (map[columnMerchant] as String?) ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(map[columnDate] as int),
      category: ExpenseCategory.fromId(map[columnCategory] as String?),
      note: map[columnNote] as String?,
      receiptPath: map[columnReceiptPath] as String?,
      rawText: map[columnRawText] as String?,
      createdAt: map[columnCreatedAt] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map[columnCreatedAt] as int),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId && id != null) columnId: id,
      columnAmount: amount,
      columnMerchant: merchant,
      columnCategory: category.id,
      columnDate: date.millisecondsSinceEpoch,
      columnNote: note,
      columnReceiptPath: receiptPath,
      columnRawText: rawText,
      columnCreatedAt:
          (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
    };
  }

  static const List<String> createTableStatements = <String>[
    '''
    CREATE TABLE $table (
      $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
      $columnAmount REAL NOT NULL,
      $columnMerchant TEXT NOT NULL,
      $columnCategory TEXT NOT NULL,
      $columnDate INTEGER NOT NULL,
      $columnNote TEXT,
      $columnReceiptPath TEXT,
      $columnRawText TEXT,
      $columnCreatedAt INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_expenses_date ON $table ($columnDate DESC)',
    'CREATE INDEX idx_expenses_category ON $table ($columnCategory)',
  ];
}
