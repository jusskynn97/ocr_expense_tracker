import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../../domain/entities/parsed_receipt.dart';
import '../../domain/services/receipt_understander.dart';

/// Trợ lý AI on-device dùng LiteRT-LM + model ngôn ngữ nhỏ LFM2.5-230M.
///
/// Cách hoạt động: regex luôn chạy trước và cho kết quả ngay. Khi model đã sẵn
/// sàng, [refine] đưa văn bản OCR cùng **danh sách ứng viên** mà regex đã tìm
/// được cho model chọn lại - model không được phép bịa giá trị mới. Mọi câu
/// trả lời không khớp ứng viên (hoặc không xuất hiện trong văn bản gốc) đều bị
/// bỏ qua, nhờ vậy trợ lý không thể làm hỏng kết quả đang tốt.
class LiteRtReceiptUnderstander implements ReceiptUnderstander {
  /// Bản int4 (~168 MB) - đa ngôn ngữ, đủ nhẹ để chạy trên điện thoại tầm trung.
  static const String _modelUrl =
      'https://huggingface.co/litert-community/LFM2.5-230M/resolve/main/'
      'LFM2.5-230M_int4.litertlm';

  /// `InferenceInstallation.modelId` là tên file không kèm phần mở rộng.
  static const String modelId = 'LFM2.5-230M_int4';

  static const int _maxTokens = 2048;

  /// Giới hạn văn bản đưa vào model để không tràn context window.
  static const int _maxPromptChars = 1200;

  static const String _systemInstruction =
      'Bạn là bộ trích xuất dữ liệu hoá đơn. Chỉ trả về một đối tượng JSON, '
      'không giải thích, không thêm chữ nào khác.';

  InferenceModel? _model;
  SlmStatus _status = SlmStatus.notInstalled;
  String? _lastError;
  Future<void>? _preparing;
  bool _refining = false;

  @override
  SlmStatus get status => _status;

  /// Thông báo lỗi gần nhất (dùng cho UI), null khi mọi thứ bình thường.
  @override
  String? get lastError => _lastError;

  @override
  bool get isReady => _model != null;

  @override
  Future<void> prepare({void Function(double progress)? onProgress}) {
    if (isReady) return Future<void>.value();
    final Future<void>? inFlight = _preparing;
    if (inFlight != null) return inFlight;

    final Future<void> task = _prepare(onProgress);
    _preparing = task.whenComplete(() => _preparing = null);
    return _preparing!;
  }

  Future<void> _prepare(void Function(double)? onProgress) async {
    _lastError = null;
    try {
      _status = SlmStatus.downloading;
      _report(onProgress, 0);

      if (!await FlutterEdgeAi.isModelInstalled(modelId)) {
        await FlutterEdgeAi.installModel(
          modelType: ModelType.general,
          fileType: ModelFileType.litertlm,
        )
            .fromNetwork(_modelUrl)
            .withProgress((int percent) => _report(onProgress, percent / 100))
            .install(activate: true);
      }

      _status = SlmStatus.loading;
      _report(onProgress, 1);

      _model = await FlutterEdgeAi.getActiveModel(
        maxTokens: _maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );
      _status = SlmStatus.ready;
    } catch (error) {
      _model = null;
      _status = SlmStatus.failed;
      _lastError = '$error';
    }
  }

  @override
  Future<ParsedReceipt> refine({
    required String rawText,
    required ParsedReceipt baseline,
  }) async {
    final InferenceModel? model = _model;
    if (model == null || _refining || rawText.trim().isEmpty) return baseline;

    _refining = true;
    InferenceChat? chat;
    try {
      chat = await model.createChat(
        temperature: 0,
        topK: 1,
        maxOutputTokens: 160,
        systemInstruction: _systemInstruction,
      );
      // `isUser: true` là bắt buộc: thiếu cờ này model trả về rỗng.
      await chat.addQueryChunk(
        Message.text(text: _buildPrompt(rawText, baseline), isUser: true),
      );

      final StringBuffer answer = StringBuffer();
      await for (final ModelResponse chunk in chat.generateChatResponseAsync()) {
        if (chunk is TextResponse) answer.write(chunk.token);
      }

      return _apply(answer.toString(), baseline);
    } catch (error) {
      _lastError = '$error';
      return baseline;
    } finally {
      try {
        await chat?.close();
      } catch (_) {
        // Phiên có thể chưa kịp tạo; không cần xử lý.
      }
      _refining = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Prompt
  // ---------------------------------------------------------------------------

  String _buildPrompt(String rawText, ParsedReceipt baseline) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Trích xuất thông tin từ hoá đơn dưới đây.')
      ..writeln('--- VĂN BẢN OCR ---')
      ..writeln(_truncate(rawText))
      ..writeln('--- ỨNG VIÊN (chỉ được chọn trong danh sách này) ---')
      ..writeln('Số tiền: ${_amountOptions(baseline)}')
      ..writeln('Ngày: ${_dateOptions(baseline)}')
      ..writeln('Cửa hàng: ${_merchantOptions(baseline)}')
      ..writeln(
        'Trả về JSON: {"amount": số hoặc null, "date": "dd/mm/yyyy" hoặc null, '
        '"merchant": "tên" hoặc null}. Nếu không chắc, điền null.',
      );
    return buffer.toString();
  }

  String _amountOptions(ParsedReceipt baseline) {
    if (baseline.amountCandidates.isEmpty) return '(không có)';
    return baseline.amountCandidates
        .map((double value) => value.toStringAsFixed(0))
        .join(', ');
  }

  String _dateOptions(ParsedReceipt baseline) {
    if (baseline.dateCandidates.isEmpty) return '(không có)';
    return baseline.dateCandidates.map(_formatDate).join(', ');
  }

  String _merchantOptions(ParsedReceipt baseline) {
    if (baseline.merchantCandidates.isEmpty) return '(không có)';
    return baseline.merchantCandidates.join(' | ');
  }

  static String _formatDate(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  static String _truncate(String text) {
    final String trimmed = text.trim();
    if (trimmed.length <= _maxPromptChars) return trimmed;
    return '${trimmed.substring(0, _maxPromptChars)}…';
  }

  // ---------------------------------------------------------------------------
  // Kiểm chứng kết quả (grounding)
  // ---------------------------------------------------------------------------

  ParsedReceipt _apply(String response, ParsedReceipt baseline) {
    final Map<String, Object?>? json = _firstJsonObject(response);

    final double? amount = _groundedAmount(json?['amount'], baseline);
    final DateTime? date = _groundedDate(json?['date'], baseline);
    final String? merchant = _groundedMerchant(json?['merchant'], baseline);

    if (amount == null && date == null && merchant == null) return baseline;

    return baseline.copyWith(
      amount: amount,
      date: date,
      merchant: merchant,
      refinedByModel: true,
    );
  }

  /// Lấy đối tượng JSON đầu tiên trong câu trả lời (model nhỏ hay thêm chữ thừa).
  Map<String, Object?>? _firstJsonObject(String response) {
    final int start = response.indexOf('{');
    final int end = response.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final Object? decoded = jsonDecode(response.substring(start, end + 1));
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Số tiền chỉ được nhận khi khớp một ứng viên regex đã tìm, hoặc (khi regex
  /// không tìm được số nào) xuất hiện nguyên vẹn trong văn bản OCR.
  double? _groundedAmount(Object? value, ParsedReceipt baseline) {
    final double? parsed = _toDouble(value);
    if (parsed == null || parsed <= 0) return null;

    for (final double candidate in baseline.amountCandidates) {
      if ((candidate - parsed).abs() < 0.5) return candidate;
    }
    if (baseline.amountCandidates.isEmpty &&
        _appearsInText(parsed.toStringAsFixed(0), baseline.rawText)) {
      return parsed;
    }
    return null;
  }

  /// Ngày phải trùng một ứng viên, hoặc là ngày có thật trong văn bản OCR.
  DateTime? _groundedDate(Object? value, ParsedReceipt baseline) {
    final DateTime? parsed = _parseDate(value);
    if (parsed == null) return null;

    for (final DateTime candidate in baseline.dateCandidates) {
      if (_sameDay(candidate, parsed)) return candidate;
    }
    if (baseline.dateCandidates.isEmpty &&
        _containsLiteral(_formatDate(parsed), baseline.rawText)) {
      return parsed;
    }
    return null;
  }

  /// Tên cửa hàng phải là một trong các dòng regex đã coi là ứng viên.
  String? _groundedMerchant(Object? value, ParsedReceipt baseline) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    if (trimmed.length < 3 || trimmed.length > 60) return null;

    final String needle = _normalize(trimmed);
    for (final String candidate in baseline.merchantCandidates) {
      if (_normalize(candidate) == needle) return candidate;
    }
    if (baseline.merchantCandidates.isEmpty &&
        _normalize(baseline.rawText).contains(needle)) {
      return trimmed;
    }
    return null;
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), ''));
    }
    return null;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    final RegExpMatch? match =
        RegExp(r'(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4})')
            .firstMatch(value);
    if (match == null) return null;

    final int day = int.parse(match.group(1)!);
    final int month = int.parse(match.group(2)!);
    final int year = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final DateTime parsed = DateTime(year, month, day);
    if (parsed.month != month || parsed.day != day) return null;
    return parsed;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Số/ngày chỉ được coi là "có trong văn bản" khi khớp trọn một cụm số,
  /// tránh trường hợp "125" khớp nhầm bên trong "125000".
  static bool _appearsInText(String needle, String haystack) {
    final String digits = needle.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return false;
    final RegExp pattern = RegExp('(?<![\\d])$digits(?![\\d])');
    return pattern.hasMatch(haystack.replaceAll(RegExp(r'[.,\s]'), ''));
  }

  /// So khớp nguyên văn nhưng bỏ qua khác biệt về dấu phân cách ngày
  /// (`21/10/2025` khớp cả `21-10-2025`) và khoảng trắng thừa.
  static bool _containsLiteral(String needle, String haystack) {
    String canonical(String value) => value
        .replaceAll(RegExp(r'[-.]'), '/')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return canonical(haystack).contains(canonical(needle));
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  void _report(void Function(double)? onProgress, double value) {
    onProgress?.call(value.clamp(0, 1).toDouble());
  }
}
