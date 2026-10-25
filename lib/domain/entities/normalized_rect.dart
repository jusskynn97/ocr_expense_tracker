/// Hình chữ nhật chuẩn hoá (0.0 - 1.0) mô tả vùng crop trên khung ngắm camera.
class NormalizedRect {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Vùng crop mặc định: 88% chiều ngang, 46% chiều cao, canh giữa.
  static const NormalizedRect receiptFrame = NormalizedRect(
    left: 0.06,
    top: 0.27,
    width: 0.88,
    height: 0.46,
  );

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  /// Đổi sang pixel trên ảnh gốc.
  int x(int imageWidth) => (left * imageWidth).round().clamp(0, imageWidth - 1);
  int y(int imageHeight) => (top * imageHeight).round().clamp(0, imageHeight - 1);
  int w(int imageWidth) => (width * imageWidth).round().clamp(1, imageWidth);
  int h(int imageHeight) => (height * imageHeight).round().clamp(1, imageHeight);
}
