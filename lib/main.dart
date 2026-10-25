import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/datasources/expense_local_data_source.dart';
import 'data/repositories/expense_repository_impl.dart';
import 'data/services/file_receipt_image_store.dart';
import 'data/services/heuristic_receipt_parser.dart';
import 'data/services/mlkit_text_recognizer_service.dart';
import 'domain/repositories/expense_repository.dart';
import 'domain/services/receipt_image_store.dart';
import 'domain/usecases/create_expense.dart';
import 'domain/usecases/delete_expense.dart';
import 'domain/usecases/get_expenses.dart';
import 'domain/usecases/scan_receipt.dart';
import 'domain/usecases/update_expense.dart';
import 'presentation/pages/home_shell_page.dart';
import 'presentation/providers/expense_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpenseTrackerApp());
}

/// Điểm khởi tạo duy nhất: lắp ráp phụ thuộc (DI thủ công) rồi bơm vào cây widget.
class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  // --- Data layer ---------------------------------------------------------
  final ExpenseLocalDataSource _localDataSource = ExpenseLocalDataSource();
  late final ExpenseRepository _repository =
      ExpenseRepositoryImpl(_localDataSource);
  final ReceiptImageStore _imageStore = const FileReceiptImageStore();
  final MlkitTextRecognizerService _recognizer = MlkitTextRecognizerService();
  final HeuristicReceiptParser _parser = const HeuristicReceiptParser();

  // --- Use cases ----------------------------------------------------------
  late final GetExpensesUseCase _getExpenses = GetExpensesUseCase(_repository);
  late final CreateExpenseUseCase _createExpense =
      CreateExpenseUseCase(_repository);
  late final UpdateExpenseUseCase _updateExpense =
      UpdateExpenseUseCase(_repository);
  late final DeleteExpenseUseCase _deleteExpense =
      DeleteExpenseUseCase(_repository, _imageStore);
  late final ScanReceiptUseCase _scanReceipt =
      ScanReceiptUseCase(_recognizer, _parser);

  @override
  void dispose() {
    _recognizer.dispose();
    _localDataSource.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ReceiptImageStore>.value(value: _imageStore),
        Provider<CreateExpenseUseCase>.value(value: _createExpense),
        Provider<ScanReceiptUseCase>.value(value: _scanReceipt),
        ChangeNotifierProvider<ExpenseProvider>(
          create: (_) => ExpenseProvider(
            getExpenses: _getExpenses,
            createExpense: _createExpense,
            updateExpense: _updateExpense,
            deleteExpense: _deleteExpense,
          )..load(),
        ),
      ],
      child: MaterialApp(
        title: 'OCR Expense Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const HomeShellPage(),
      ),
    );
  }
}
