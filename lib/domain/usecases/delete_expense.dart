import '../repositories/expense_repository.dart';
import '../services/receipt_image_store.dart';

class DeleteExpenseUseCase {
  const DeleteExpenseUseCase(this._repository, this._imageStore);

  final ExpenseRepository _repository;
  final ReceiptImageStore _imageStore;

  /// Xoá chi tiêu, đồng thời dọn ảnh hoá đơn đã cache (nếu có).
  Future<void> call(int id) async {
    final expense = await _repository.getExpense(id);
    await _repository.deleteExpense(id);
    final String? path = expense?.receiptPath;
    if (path != null && path.isNotEmpty) {
      await _imageStore.remove(path);
    }
  }
}
