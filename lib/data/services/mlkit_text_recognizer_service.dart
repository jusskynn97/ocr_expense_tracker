import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/services/text_recognizer_service.dart';

/// Nhận diện văn bản on-device bằng Google ML Kit (model tải sẵn, chạy offline).
///
/// ML Kit trả về từng khối văn bản kèm `boundingBox`. Nếu chỉ nối thẳng
/// `line.text` theo thứ tự, hoá đơn dạng hai cột (nhãn bên trái, giá bên phải)
/// sẽ bị tách thành hai dòng riêng - đúng nguyên nhân khiến regex không thấy
/// được cặp "Tổng cộng" + "125.000" nằm cùng hàng.
///
/// Vì vậy service này dựng lại bố cục: gom các dòng có cùng độ cao thị giác
/// thành một hàng, sắp xếp theo trục ngang và chèn khoảng trắng theo độ rộng
/// khe hở để giữ tương quan cột.
class MlkitTextRecognizerService implements TextRecognizerService {
  MlkitTextRecognizerService({TextRecognitionScript script = TextRecognitionScript.latin})
      : _script = script;

  final TextRecognitionScript _script;
  TextRecognizer? _recognizer;

  TextRecognizer get _instance =>
      _recognizer ??= TextRecognizer(script: _script);

  @override
  Future<String> extractText(String imagePath) async {
    final InputImage inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognized = await _instance.processImage(inputImage);

    final List<_PositionedLine> lines = <_PositionedLine>[];
    for (final TextBlock block in recognized.blocks) {
      for (final TextLine line in block.lines) {
        final String text = line.text.trim();
        if (text.isEmpty) continue;
        lines.add(_PositionedLine(text: text, box: line.boundingBox));
      }
    }

    if (lines.isEmpty) return recognized.text.trim();

    return _rebuildLayout(lines);
  }

  /// Gom các dòng cùng hàng thị giác rồi nối lại thành văn bản giữ cột.
  String _rebuildLayout(List<_PositionedLine> lines) {
    lines.sort((_PositionedLine a, _PositionedLine b) {
      final int byTop = a.box.top.compareTo(b.box.top);
      if (byTop != 0) return byTop;
      return a.box.left.compareTo(b.box.left);
    });

    final StringBuffer buffer = StringBuffer();
    final List<_PositionedLine> row = <_PositionedLine>[];
    double rowBottom = 0;

    void flushRow() {
      if (row.isEmpty) return;
      buffer.writeln(_joinRow(row));
      row.clear();
    }

    for (final _PositionedLine line in lines) {
      // Cùng hàng khi tâm dọc của dòng vẫn nằm trong dải của hàng đang mở.
      final bool sameRow = row.isNotEmpty && line.box.top < rowBottom;
      if (!sameRow) {
        flushRow();
        row.add(line);
        rowBottom = line.box.bottom;
        continue;
      }
      row.add(line);
      rowBottom = rowBottom > line.box.bottom ? rowBottom : line.box.bottom;
    }
    flushRow();

    return buffer.toString().trim();
  }

  /// Nối các mảnh trong một hàng, chèn khoảng trắng tương ứng độ rộng khe hở.
  String _joinRow(List<_PositionedLine> row) {
    row.sort((_PositionedLine a, _PositionedLine b) =>
        a.box.left.compareTo(b.box.left));

    final StringBuffer buffer = StringBuffer();
    _PositionedLine? previous;
    for (final _PositionedLine line in row) {
      if (previous == null) {
        buffer.write(line.text);
      } else {
        buffer.write(' ' * _gapSpaces(previous, line));
        buffer.write(line.text);
      }
      previous = line;
    }
    return buffer.toString().trimRight();
  }

  /// Ước lượng số khoảng trắng cần chèn từ khe hở ngang giữa hai mảnh.
  int _gapSpaces(_PositionedLine left, _PositionedLine right) {
    final double gap = right.box.left - left.box.right;
    // Bề rộng một ký tự ~ 0.55 chiều cao dòng (đủ tốt cho font hoá đơn).
    final double charWidth = left.box.height * 0.55;
    if (charWidth <= 0) return 1;
    final int spaces = (gap / charWidth).round();
    // Ít nhất 1 (hai mảnh khác nhau), nhiều nhất 12 để không phá dòng.
    return spaces.clamp(1, 12).toInt();
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}

class _PositionedLine {
  const _PositionedLine({required this.text, required this.box});

  final String text;
  final Rect box;
}
