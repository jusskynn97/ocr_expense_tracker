import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/normalized_rect.dart';
import '../../domain/services/receipt_image_store.dart';

/// Crop + nén ảnh hoá đơn rồi lưu vào `<app documents>/receipts`.
///
/// Toàn bộ xử lý diễn ra on-device bằng package `image` (thuần Dart),
/// không cần native plugin và không upload ảnh lên đâu cả.
class FileReceiptImageStore implements ReceiptImageStore {
  const FileReceiptImageStore({this.maxWidth = 1024, this.quality = 82});

  static const String _folderName = 'receipts';

  final int maxWidth;
  final int quality;

  @override
  Future<String> persist({
    required String sourcePath,
    NormalizedRect? crop,
  }) async {
    final File source = File(sourcePath);
    if (!source.existsSync()) {
      throw const ReceiptImageException('Không tìm thấy ảnh vừa chụp.');
    }

    final img.Image? decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) {
      throw const ReceiptImageException('Không đọc được định dạng ảnh.');
    }

    // Áp dụng EXIF orientation để toạ độ crop khớp với khung ngắm.
    img.Image processed = img.bakeOrientation(decoded);

    if (crop != null) {
      processed = _applyCrop(processed, crop);
    }

    if (processed.width > maxWidth) {
      processed = img.copyResize(
        processed,
        width: maxWidth,
        interpolation: img.Interpolation.average,
      );
    }

    final Directory directory = await _receiptDirectory();
    final String fileName =
        'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final File target = File(p.join(directory.path, fileName));
    await target.writeAsBytes(img.encodeJpg(processed, quality: quality));
    return target.path;
  }

  @override
  Future<void> remove(String path) async {
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  img.Image _applyCrop(img.Image image, NormalizedRect crop) {
    final int x = crop.x(image.width);
    final int y = crop.y(image.height);
    int width = crop.w(image.width);
    int height = crop.h(image.height);

    width = width.clamp(1, image.width - x);
    height = height.clamp(1, image.height - y);
    if (width < 8 || height < 8) return image;

    return img.copyCrop(image, x: x, y: y, width: width, height: height);
  }

  Future<Directory> _receiptDirectory() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(documents.path, _folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}

class ReceiptImageException implements Exception {
  const ReceiptImageException(this.message);

  final String message;

  @override
  String toString() => message;
}
