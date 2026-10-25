/// Nhận diện văn bản on-device (ML Kit). Không gọi cloud.
abstract interface class TextRecognizerService {
  /// Trả về text đã sắp xếp theo thứ tự đọc (trên -> dưới, trái -> phải).
  Future<String> extractText(String imagePath);

  Future<void> dispose();
}
