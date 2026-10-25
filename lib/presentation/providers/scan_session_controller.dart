import 'package:flutter/foundation.dart';

import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_category.dart';
import '../../domain/entities/normalized_rect.dart';
import '../../domain/entities/parsed_receipt.dart';
import '../../domain/services/receipt_image_store.dart';
import '../../domain/usecases/create_expense.dart';
import '../../domain/usecases/scan_receipt.dart';

/// Các bước của một phiên quét hoá đơn.
enum ScanStage { cropping, recognizing, ready, failed }

/// Điều khiển luồng: crop ảnh -> OCR + regex -> form review -> lưu.
class ScanSessionController extends ChangeNotifier {
  ScanSessionController({
    required ScanReceiptUseCase scanReceipt,
    required CreateExpenseUseCase createExpense,
    required ReceiptImageStore imageStore,
    required this.sourceImagePath,
    this.crop,
  })  : _scanReceipt = scanReceipt,
        _createExpense = createExpense,
        _imageStore = imageStore;

  final ScanReceiptUseCase _scanReceipt;
  final CreateExpenseUseCase _createExpense;
  final ReceiptImageStore _imageStore;

  final String sourceImagePath;
  final NormalizedRect? crop;

  ScanStage _stage = ScanStage.cropping;
  String? _receiptPath;
  ScanResult _result = ScanResult.empty;
  String? _errorMessage;
  bool _saving = false;
  bool _saved = false;
  bool _disposed = false;

  ScanStage get stage => _stage;
  String? get receiptPath => _receiptPath;
  ParsedReceipt get parsed => _result.receipt;
  ExpenseCategory get suggestedCategory => _result.suggestedCategory;
  String? get errorMessage => _errorMessage;
  bool get isSaving => _saving;
  bool get isBusy => _stage == ScanStage.cropping || _stage == ScanStage.recognizing;

  /// Chạy toàn bộ pipeline on-device. An toàn khi gọi lại nhiều lần.
  Future<void> start() async {
    if (_stage == ScanStage.ready || _stage == ScanStage.recognizing) return;
    _stage = ScanStage.cropping;
    _errorMessage = null;
    _safeNotify();

    try {
      _receiptPath = await _imageStore.persist(
        sourcePath: sourceImagePath,
        crop: crop,
      );
      _stage = ScanStage.recognizing;
      _safeNotify();

      _result = await _scanReceipt(_receiptPath!);
      _stage = ScanStage.ready;
    } catch (error) {
      _stage = ScanStage.failed;
      _errorMessage = '$error';
    }
    _safeNotify();
  }

  /// Lưu chi tiêu đã được người dùng xác nhận/chỉnh sửa.
  Future<Expense> save(Expense draft) async {
    _saving = true;
    _safeNotify();
    try {
      final Expense created = await _createExpense(
        draft.copyWith(receiptPath: _receiptPath, rawText: parsed.rawText),
      );
      _saved = true;
      return created;
    } finally {
      _saving = false;
      _safeNotify();
    }
  }

  /// Xoá ảnh tạm nếu người dùng bỏ phiên quét.
  Future<void> discard() async {
    final String? path = _receiptPath;
    _receiptPath = null;
    if (!_saved && path != null) {
      await _imageStore.remove(path);
    }
  }

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
