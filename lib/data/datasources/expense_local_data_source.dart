import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/expense.dart';
import '../models/expense_model.dart';

/// Nguồn dữ liệu cục bộ (SQLite) cho chi tiêu.
class ExpenseLocalDataSource {
  ExpenseLocalDataSource({DatabaseFactory? factory, String? databasePath})
      : _factory = factory,
        _explicitPath = databasePath;

  static const String _databaseName = 'ocr_expense_tracker.db';
  static const int _databaseVersion = 1;

  final DatabaseFactory? _factory;
  final String? _explicitPath;

  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final String path =
        _explicitPath ?? p.join(await getDatabasesPath(), _databaseName);
    final DatabaseFactory factory = _factory ?? databaseFactory;
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database db, int version) async {
          for (final String statement in ExpenseModel.createTableStatements) {
            await db.execute(statement);
          }
        },
      ),
    );
  }

  Future<List<Expense>> fetchExpenses({DateTime? from, DateTime? to}) async {
    final Database db = await database;
    final List<String> clauses = <String>[];
    final List<Object?> args = <Object?>[];

    if (from != null) {
      clauses.add('${ExpenseModel.columnDate} >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      clauses.add('${ExpenseModel.columnDate} <= ?');
      args.add(to.millisecondsSinceEpoch);
    }

    final List<Map<String, Object?>> rows = await db.query(
      ExpenseModel.table,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: '${ExpenseModel.columnDate} DESC, ${ExpenseModel.columnId} DESC',
    );

    return rows.map(ExpenseModel.fromMap).toList();
  }

  Future<Expense?> findById(int id) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      ExpenseModel.table,
      where: '${ExpenseModel.columnId} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ExpenseModel.fromMap(rows.first);
  }

  Future<int> insert(Expense expense) async {
    final Database db = await database;
    return db.insert(ExpenseModel.table, ExpenseModel.fromEntity(expense).toMap());
  }

  Future<void> update(Expense expense) async {
    final Database db = await database;
    await db.update(
      ExpenseModel.table,
      ExpenseModel.fromEntity(expense).toMap(),
      where: '${ExpenseModel.columnId} = ?',
      whereArgs: <Object?>[expense.id],
    );
  }

  Future<void> delete(int id) async {
    final Database db = await database;
    await db.delete(
      ExpenseModel.table,
      where: '${ExpenseModel.columnId} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteAll() async {
    final Database db = await database;
    await db.delete(ExpenseModel.table);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
