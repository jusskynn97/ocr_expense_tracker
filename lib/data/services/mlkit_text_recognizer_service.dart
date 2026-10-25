import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/services/text_recognizer_service.dart';

/// Nhận diện văn bản on-device bằng Google ML Kit (model tải sẵn, chạy offline).
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

    final List<TextBlock> blocks = List<TextBlock>.of(recognized.blocks)
      ..sort((TextBlock a, TextBlock b) {
        final int byTop = a.boundingBox.top.compareTo(b.boundingBox.top);
        if (byTop != 0) return byTop;
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      });

    if (blocks.isEmpty) return recognized.text;

    // Sắp xếp lại theo toạ độ để dòng đọc ra khớp bố cục hoá đơn.
    final StringBuffer buffer = StringBuffer();
    for (final TextBlock block in blocks) {
      final List<TextLine> lines = List<TextLine>.of(block.lines)
        ..sort((TextLine a, TextLine b) =>
            a.boundingBox.top.compareTo(b.boundingBox.top));
      for (final TextLine line in lines) {
        buffer.writeln(line.text);
      }
    }
    return buffer.toString().trim();
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
