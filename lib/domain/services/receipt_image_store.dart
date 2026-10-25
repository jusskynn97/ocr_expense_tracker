import '../entities/normalized_rect.dart';

/// Lưu trữ ảnh hoá đơn đã crop vào thư mục ứng dụng (cache thumbnail).
abstract interface class ReceiptImageStore {
  /// Crop theo [crop], resize thành thumbnail JPEG và trả về đường dẫn tuyệt đối.
  Future<String> persist({required String sourcePath, NormalizedRect? crop});

  Future<void> remove(String path);
}
