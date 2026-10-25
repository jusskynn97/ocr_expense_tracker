import 'package:flutter/foundation.dart';

import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_category.dart';
import '../../domain/entities/normalized_rect.dart';
import '../../domain/entities/parsed_receipt.dart';
import '../../domain/services/receipt_image_store.dart';
import '../../domain/services/receipt_understander.dart';
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
    ReceiptUnderstander? understander,
  })  : _scanReceipt = scanReceipt,
        _createExpense = createExpense,
        _imageStore = imageStore,
        _understander = understander,
        _assistantStatus = understander?.isReady ?? false
            ? SlmStatus.ready
            : SlmStatus.notInstalled;

  final ScanReceiptUseCase _scanReceipt;
  final CreateExpenseUseCase _createExpense;
  final ReceiptImageStore _imageStore;

  /// Trợ lý AI on-device (có thể null nếu nền tảng không hỗ trợ).
  final ReceiptUnderstander? _understander;

  final String sourceImagePath;
  final NormalizedRect? crop;

  ScanStage _stage = ScanStage.cropping;
  String? _receiptPath;
  ScanResult _result = ScanResult.empty;
  String? _errorMessage;
  bool _saving = false;
  bool _saved = false;
  bool _disposed = false;

  SlmStatus _assistantStatus;
  double _assistantProgress = 0;
  bool _assistantRunning = false;

  ScanStage get stage => _stage;
  String? get receiptPath => _receiptPath;
  ParsedReceipt get parsed => _result.receipt;
  ExpenseCategory get suggestedCategory => _result.suggestedCategory;
  String? get errorMessage => _errorMessage;
  bool get isSaving => _saving;
  bool get isBusy => _stage == ScanStage.cropping || _stage == ScanStage.recognizing;

  /// Máy này có trợ lý AI on-device để tinh chỉnh kết quả hay không.
  bool get hasAssistant => _understander != null;
  SlmStatus get assistantStatus => _assistantStatus;
  double get assistantProgress => _assistantProgress;
  bool get isAssistantBusy =>
      _assistantRunning ||
      _assistantStatus == SlmStatus.downloading ||
      _assistantStatus == SlmStatus.loading;
  String? get assistantError => _understander?.lastError;

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

  /// Tải/nạp model rồi nhờ nó đối chiếu lại kết quả regex đang có.
  ///
  /// Dùng chung cho cả lần bật đầu tiên và lần thử lại sau khi lỗi.
  Future<void> enableAssistant() async {
    final ReceiptUnderstander? understander = _understander;
    if (understander == null || _assistantRunning) return;

    _assistantRunning = true;
    _assistantProgress = 0;
    _safeNotify();

    try {
      await understander.prepare(
        onProgress: (double progress) {
          _assistantProgress = progress;
          _assistantStatus = understander.status;
          _safeNotify();
        },
      );

      if (understander.isReady) {
        _result = await _scanReceipt.refineOnly(_result);
      }
    } catch (error) {
      _errorMessage = null;
      debugPrint('Trợ lý AI on-device thất bại: $error');
    } finally {
      _assistantStatus = understander.status;
      _assistantRunning = false;
      _safeNotify();
    }
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
