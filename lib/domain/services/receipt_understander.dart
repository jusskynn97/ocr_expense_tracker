import '../entities/parsed_receipt.dart';

/// Trạng thái của trợ lý AI on-device (model ngôn ngữ nhỏ - SLM).
enum SlmStatus {
  /// Chưa cài model - cần tải về trước khi dùng.
  notInstalled,

  /// Đang tải model từ mạng (chỉ xảy ra một lần cho mỗi máy).
  downloading,

  /// Đang nạp model vào bộ nhớ.
  loading,

  /// Sẵn sàng đối chiếu kết quả.
  ready,

  /// Tải/nạp thất bại (thiếu mạng, hết dung lượng, máy không hỗ trợ…).
  failed,
}

/// Cổng (port) cho bộ hiểu hoá đơn bằng model ngôn ngữ nhỏ chạy on-device.
///
/// Thiết kế hybrid: regex luôn chạy trước và cho kết quả ngay, nên ứng dụng
/// hoạt động bình thường kể cả khi chưa tải model. Khi model sẵn sàng, nó đọc
/// lại văn bản OCR và **chỉ được phép chọn trong số các ứng viên** mà regex đã
/// tìm ra - nhờ vậy không thể bịa ra số tiền/ngày không có trên hoá đơn.
abstract interface class ReceiptUnderstander {
  /// Model đã được cài và nạp thành công chưa. Đọc đồng bộ, không gây I/O.
  bool get isReady;

  /// Trạng thái hiện tại, để giao diện phản ánh tiến trình tải/nạp model.
  SlmStatus get status;

  /// Thông báo lỗi gần nhất, null khi không có lỗi.
  String? get lastError;

  /// Tải và nạp model nếu chưa có. An toàn khi gọi lại nhiều lần.
  ///
  /// [onProgress] nhận tiến độ tải trong khoảng 0..1.
  Future<void> prepare({void Function(double progress)? onProgress});

  /// Nhờ model đọc [rawText] và tinh chỉnh [baseline].
  ///
  /// Không bao giờ ném lỗi: nếu model không sẵn sàng, trả lời không phân tích
  /// được, hoặc kết quả không khớp với văn bản gốc thì trả lại [baseline].
  Future<ParsedReceipt> refine({
    required String rawText,
    required ParsedReceipt baseline,
  });
}
