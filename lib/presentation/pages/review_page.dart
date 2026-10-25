import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_category.dart';
import '../../domain/entities/normalized_rect.dart';
import '../../domain/entities/parsed_receipt.dart';
import '../../domain/services/receipt_image_store.dart';
import '../../domain/services/receipt_understander.dart';
import '../../domain/usecases/create_expense.dart';
import '../../domain/usecases/scan_receipt.dart';
import '../providers/expense_provider.dart';
import '../providers/scan_session_controller.dart';
import '../widgets/app_tap_scale.dart';
import '../widgets/category_visuals.dart';
import '../widgets/expense_tile.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/shimmer_box.dart';
import '../widgets/staggered_entry.dart';
import '../widgets/success_check.dart';

/// Màn hình xác nhận: OCR + regex chạy on-device, người dùng chỉnh sửa rồi lưu.
class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key, required this.imagePath, this.crop});

  final String imagePath;
  final NormalizedRect? crop;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScanSessionController>(
      create: (BuildContext context) => ScanSessionController(
        scanReceipt: context.read<ScanReceiptUseCase>(),
        createExpense: context.read<CreateExpenseUseCase>(),
        imageStore: context.read<ReceiptImageStore>(),
        understander: context.read<ReceiptUnderstander?>(),
        sourceImagePath: imagePath,
        crop: crop,
      )..start(),
      child: const _ReviewView(),
    );
  }
}

class _ReviewView extends StatefulWidget {
  const _ReviewView();

  @override
  State<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<_ReviewView> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _merchant = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final FocusNode _merchantFocus = FocusNode();

  late final ScanSessionController _session;

  DateTime _date = DateTime.now();
  ExpenseCategory _category = ExpenseCategory.food;
  bool _populated = false;
  bool _showRawText = false;
  bool _saved = false;
  bool _discarded = false;

  /// Người dùng đã tự sửa trường nào thì trợ lý AI không được ghi đè trường đó.
  bool _amountEdited = false;
  bool _merchantEdited = false;
  bool _dateEdited = false;
  bool _refinementApplied = false;

  @override
  void initState() {
    super.initState();
    _session = context.read<ScanSessionController>();
    _session.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    _merchantFocus.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    _syncFromSession();
    _syncRefinement();
  }

  /// Khi OCR xong, đổ dữ liệu bóc tách vào form (chỉ một lần).
  void _syncFromSession() {
    if (!mounted || _populated) return;
    if (_session.stage != ScanStage.ready) return;

    final ParsedReceipt parsed = _session.parsed;
    _populated = true;
    setState(() {
      final double? amount = parsed.amount;
      _amount.text = amount == null ? '' : CurrencyFormatter.thousands(amount);
      _merchant.text = parsed.merchant ?? '';
      _note.text = '';
      _date = parsed.date ?? DateTime.now();
      _category = _session.suggestedCategory;
    });
  }

  /// Trợ lý AI chạy xong sau khi form đã hiện: chỉ cập nhật những trường người
  /// dùng chưa đụng tới, để không xoá công chỉnh sửa tay của họ.
  void _syncRefinement() {
    if (!mounted || !_populated || _refinementApplied) return;

    final ParsedReceipt parsed = _session.parsed;
    if (!parsed.refinedByModel) return;
    _refinementApplied = true;

    setState(() {
      final double? amount = parsed.amount;
      if (!_amountEdited && amount != null) {
        _amount.text = CurrencyFormatter.thousands(amount);
      }
      final String? merchant = parsed.merchant;
      if (!_merchantEdited && merchant != null && merchant.isNotEmpty) {
        _merchant.text = merchant;
      }
      final DateTime? date = parsed.date;
      if (!_dateEdited && date != null) _date = date;
    });
  }

  // ---------------------------------------------------------------------------
  // Hành động
  // ---------------------------------------------------------------------------

  void _useCandidate(double value) {
    setState(() {
      _amountEdited = true;
      _amount.text = CurrencyFormatter.thousands(value);
      _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    });
  }

  void _useMerchantCandidate(String value) {
    setState(() {
      _merchantEdited = true;
      _merchant.text = value;
      _merchant.selection = TextSelection.collapsed(offset: value.length);
    });
  }

  void _useDateCandidate(DateTime value) {
    setState(() {
      _dateEdited = true;
      _date = value;
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: AppTheme.dark,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _dateEdited = true;
        _date = picked;
      });
    }
  }

  /// Mở ảnh hoá đơn toàn màn hình để người dùng phóng to đối chiếu.
  void _openPreview(String path) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _ReceiptZoomPage(imagePath: path),
      ),
    );
  }

  Future<void> _save() async {
    final double? amount = CurrencyFormatter.parseNumber(_amount.text);
    if (amount == null || amount <= 0) {
      _showMessage('Số tiền phải lớn hơn 0.');
      return;
    }

    final String merchant = _merchant.text.trim();
    final String note = _note.text.trim();

    setState(() {});
    try {
      await _session.save(
        Expense(
          amount: amount,
          merchant: merchant.isEmpty ? 'Không xác định' : merchant,
          date: _date,
          category: _category,
          note: note.isEmpty ? null : note,
        ),
      );
      if (!mounted) return;
      await context.read<ExpenseProvider>().load();
      if (!mounted) return;

      setState(() => _saved = true);
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Không lưu được: $error');
    }
  }

  void _useManualEntry() {
    setState(() {
      _populated = true;
      _amount.text = '';
      _merchant.text = '';
      _date = DateTime.now();
      _category = ExpenseCategory.food;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _merchantFocus.requestFocus();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surfaceHigh,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ScanSessionController session = context.watch<ScanSessionController>();

    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop && !_saved && !_discarded) {
          _discarded = true;
          _session.discard();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Container(
          decoration: const BoxDecoration(gradient: AppGradients.scene),
          child: Stack(
            children: <Widget>[
              SafeArea(
                bottom: false,
                child: Column(
                  children: <Widget>[
                    _TopBar(
                      confidence: session.parsed.confidence,
                      ready: _populated,
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                        physics: const BouncingScrollPhysics(),
                        children: <Widget>[
                          StaggeredEntry(
                            index: 0,
                            child: _ReceiptPreview(
                              imagePath: session.receiptPath,
                              fallbackPath: _session.sourceImagePath,
                              processing: session.isBusy,
                              onOpen: _openPreview,
                            ),
                          ),
                          if (session.stage == ScanStage.failed)
                            StaggeredEntry(
                              index: 1,
                              child: _ErrorCard(
                                message: session.errorMessage ??
                                    'Không nhận dạng được hoá đơn.',
                                onRetry: _session.start,
                                onManual: _useManualEntry,
                              ),
                            )
                          else if (!_populated)
                            StaggeredEntry(
                              index: 1,
                              child: _RecognizingPanel(stage: session.stage),
                            ),
                          if (_populated) ..._buildForm(session),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_saved) const _SuccessOverlay(),
            ],
          ),
        ),
        bottomNavigationBar: _populated
            ? _SaveBar(
                saving: session.isSaving,
                amount: _amount.text,
                onSave: _save,
              )
            : null,
      ),
    );
  }

  List<Widget> _buildForm(ScanSessionController session) {
    final ParsedReceipt parsed = session.parsed;
    final List<double> candidates = parsed.amountCandidates;
    final List<String> merchantCandidates = parsed.merchantCandidates;
    final List<DateTime> dateCandidates = parsed.dateCandidates;

    return <Widget>[
      StaggeredEntry(
        index: 2,
        child: _AssistantCard(
          status: session.assistantStatus,
          progress: session.assistantProgress,
          busy: session.isAssistantBusy,
          available: session.hasAssistant,
          applied: parsed.refinedByModel,
          error: session.assistantError,
          onEnable: session.enableAssistant,
        ),
      ),
      StaggeredEntry(
        index: 3,
        child: _SectionCard(
          title: 'Số tiền',
          icon: Icons.payments_rounded,
          accent: AppColors.mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        _ThousandsInputFormatter(),
                      ],
                      onChanged: (_) {
                        _amountEdited = true;
                        setState(() {});
                      },
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.8,
                      ),
                      cursorColor: AppColors.mint,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6, left: 8),
                    child: Text(
                      '₫',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mint,
                      ),
                    ),
                  ),
                ],
              ),
              if (candidates.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                const _CandidateLabel(
                  text: 'Số tiền tìm thấy trên hoá đơn',
                  color: AppColors.mint,
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: candidates
                      .take(4)
                      .map(
                        (double value) => _CandidateChip(
                          label: '${CurrencyFormatter.thousands(value)} ₫',
                          accent: AppColors.mint,
                          selected: _amount.text ==
                              CurrencyFormatter.thousands(value),
                          onTap: () => _useCandidate(value),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      StaggeredEntry(
        index: 4,
        child: _SectionCard(
          title: 'Cửa hàng',
          icon: Icons.storefront_rounded,
          accent: AppColors.sky,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _PlainField(
                controller: _merchant,
                focusNode: _merchantFocus,
                hint: 'Tên cửa hàng / nơi chi tiêu',
                icon: Icons.edit_rounded,
                onChanged: () => _merchantEdited = true,
              ),
              if (merchantCandidates.length > 1) ...<Widget>[
                const SizedBox(height: 14),
                const _CandidateLabel(
                  text: 'Có thể là tên cửa hàng',
                  color: AppColors.sky,
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: merchantCandidates
                      .take(3)
                      .map(
                        (String value) => _CandidateChip(
                          label: value,
                          accent: AppColors.sky,
                          selected: _merchant.text.trim() == value,
                          onTap: () => _useMerchantCandidate(value),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      StaggeredEntry(
        index: 5,
        child: _SectionCard(
          title: 'Ngày & nhóm chi tiêu',
          icon: Icons.event_note_rounded,
          accent: AppColors.lilac,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _DateField(
                date: _date,
                onTap: _pickDate,
                onReset: () => setState(() {
                  _dateEdited = true;
                  _date = DateTime.now();
                }),
              ),
              if (dateCandidates.length > 1) ...<Widget>[
                const SizedBox(height: 14),
                const _CandidateLabel(
                  text: 'Ngày khác trên hoá đơn',
                  color: AppColors.lilac,
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: dateCandidates
                      .take(3)
                      .map(
                        (DateTime value) => _CandidateChip(
                          label: AppDateFormatter.date(value),
                          accent: AppColors.lilac,
                          selected:
                              AppDateFormatter.isSameDay(_date, value),
                          onTap: () => _useDateCandidate(value),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 18),
              _CategorySelector(
                selected: _category,
                onSelected: (ExpenseCategory value) =>
                    setState(() => _category = value),
              ),
            ],
          ),
        ),
      ),
      StaggeredEntry(
        index: 6,
        child: _SectionCard(
          title: 'Ghi chú',
          icon: Icons.sticky_note_2_rounded,
          accent: AppColors.amber,
          child: _PlainField(
            controller: _note,
            hint: 'Thêm ghi chú (không bắt buộc)',
            icon: Icons.notes_rounded,
            maxLines: 3,
          ),
        ),
      ),
      if (parsed.rawText.trim().isNotEmpty)
        StaggeredEntry(
          index: 7,
          child: _RawTextSection(
            text: parsed.rawText,
            expanded: _showRawText,
            onToggle: () => setState(() => _showRawText = !_showRawText),
          ),
        ),
    ];
  }
}

// -----------------------------------------------------------------------------
// Thành phần giao diện
// -----------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.confidence,
    required this.ready,
    required this.onClose,
  });

  final double confidence;
  final bool ready;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: <Widget>[
          CircleIconButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            tooltip: 'Huỷ',
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Xác nhận chi tiêu',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Kiểm tra và chỉnh sửa trước khi lưu',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (ready)
            _ConfidenceBadge(confidence: confidence),
        ],
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    final double ratio = confidence.clamp(0.0, 1.0);
    final Color color = ratio >= 0.7
        ? AppColors.mint
        : ratio >= 0.4
            ? AppColors.amber
            : AppColors.danger;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: ratio),
      duration: AppDurations.slow,
      curve: kAppEmphasisCurve,
      builder: (BuildContext context, double value, Widget? _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.42)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReceiptPreview extends StatefulWidget {
  const _ReceiptPreview({
    required this.imagePath,
    required this.fallbackPath,
    required this.processing,
    required this.onOpen,
  });

  final String? imagePath;
  final String fallbackPath;
  final bool processing;
  final void Function(String path) onOpen;

  @override
  State<_ReceiptPreview> createState() => _ReceiptPreviewState();
}

class _ReceiptPreviewState extends State<_ReceiptPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beam = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.processing) _beam.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _ReceiptPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.processing && !_beam.isAnimating) {
      _beam.repeat(reverse: true);
    } else if (!widget.processing && _beam.isAnimating) {
      _beam.stop();
      _beam.value = 0;
    }
  }

  @override
  void dispose() {
    _beam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String path = widget.imagePath ?? widget.fallbackPath;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: kAppCurve,
          height: 216,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: widget.processing
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppColors.mint.withValues(alpha: 0.18),
                      blurRadius: 26,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: GestureDetector(
            onTap: widget.processing ? null : () => widget.onOpen(path),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                AnimatedSwitcher(
                  duration: AppDurations.medium,
                  child: Image.file(
                    File(path),
                    key: ValueKey<String>(path),
                    fit: BoxFit.cover,
                    errorBuilder:
                        (BuildContext context, Object error, StackTrace? _) =>
                            const ColoredBox(
                      color: AppColors.surface,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.processing)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _beam,
                        builder: (BuildContext context, Widget? _) {
                          return Align(
                            alignment: Alignment(0, -1 + 2 * _beam.value),
                            child: Container(
                              height: 46,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    AppColors.mint.withValues(alpha: 0),
                                    AppColors.mint.withValues(alpha: 0.24),
                                    AppColors.mint.withValues(alpha: 0.34),
                                    AppColors.mint.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Colors.transparent, Color(0xCC070A13)],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  bottom: 12,
                  child: _PreviewPill(
                    icon: widget.processing
                        ? Icons.document_scanner_rounded
                        : Icons.crop_rounded,
                    label: widget.processing
                        ? 'Đang xử lý ảnh hoá đơn…'
                        : 'Ảnh hoá đơn đã cắt',
                    keyValue: ValueKey<bool>(widget.processing),
                    accent: AppColors.mint,
                  ),
                ),
                if (!widget.processing)
                  const Positioned(
                    right: 14,
                    bottom: 12,
                    child: _PreviewPill(
                      icon: Icons.zoom_in_rounded,
                      label: 'Chạm để xem lớn',
                      keyValue: ValueKey<String>('zoom'),
                      accent: AppColors.sky,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nhãn nhỏ nổi trên ảnh xem trước hoá đơn.
class _PreviewPill extends StatelessWidget {
  const _PreviewPill({
    required this.icon,
    required this.label,
    required this.keyValue,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Key keyValue;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: AppDurations.fast,
            child: Text(
              label,
              key: keyValue,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trang xem ảnh hoá đơn toàn màn hình, hỗ trợ phóng to để đọc số tiền nhỏ.
class _ReceiptZoomPage extends StatelessWidget {
  const _ReceiptZoomPage({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? _,
                  ) =>
                      const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textMuted,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  CircleIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                    tooltip: 'Đóng',
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Chụm hai ngón để phóng to',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel tiến trình OCR: cho người dùng biết hệ thống đang ở bước nào.
class _RecognizingPanel extends StatelessWidget {
  const _RecognizingPanel({required this.stage});

  final ScanStage stage;

  static const List<(String, String)> _steps = <(String, String)>[
    ('Cắt & tối ưu ảnh', 'Tách khung hoá đơn khỏi nền'),
    ('Nhận dạng văn bản', 'ML Kit OCR chạy ngay trên thiết bị'),
    ('Trích xuất dữ liệu', 'Bóc số tiền, ngày và tên cửa hàng'),
  ];

  /// Bước đang chạy: 0 = crop ảnh, 1 = OCR + regex.
  int get _activeIndex => stage == ScanStage.cropping ? 0 : 1;

  @override
  Widget build(BuildContext context) {
    final int activeIndex = _activeIndex;

    return Column(
      children: <Widget>[
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const _SpinningChip(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Đang nhận dạng văn bản…',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          activeIndex == 0
                              ? 'Đang chuẩn bị và cắt ảnh hoá đơn…'
                              : 'ML Kit xử lý ngay trên thiết bị, không cần mạng.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              for (int i = 0; i < _steps.length; i++)
                _OcrStepRow(
                  label: _steps[i].$1,
                  caption: _steps[i].$2,
                  done: i < activeIndex,
                  active: i == activeIndex,
                  last: i == _steps.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (int i = 0; i < 3; i++) ...<Widget>[
          const ShimmerBox(height: 92, radius: AppRadius.lg),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// Một bước trong tiến trình OCR (dấu tròn + nhãn + đường nối dọc).
class _OcrStepRow extends StatelessWidget {
  const _OcrStepRow({
    required this.label,
    required this.caption,
    required this.done,
    required this.active,
    required this.last,
  });

  final String label;
  final String caption;
  final bool done;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              _marker(),
              if (!last)
                Expanded(
                  child: AnimatedContainer(
                    duration: AppDurations.medium,
                    curve: kAppCurve,
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: done
                          ? AppColors.mint.withValues(alpha: 0.55)
                          : AppColors.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AnimatedDefaultTextStyle(
                    duration: AppDurations.fast,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: done || active
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                    child: Text(label),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _marker() {
    if (done) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppGradients.mint,
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 16,
          color: Color(0xFF04231C),
        ),
      );
    }
    if (active) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.mint.withValues(alpha: 0.14),
          border: Border.all(color: AppColors.mint, width: 1.5),
        ),
        child: const Padding(
          padding: EdgeInsets.all(7),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.mint,
          ),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.outline, width: 1.4),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SpinningChip extends StatefulWidget {
  const _SpinningChip();

  @override
  State<_SpinningChip> createState() => _SpinningChipState();
}

class _SpinningChipState extends State<_SpinningChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              transform: GradientRotation(_controller.value * 6.28318),
              colors: const <Color>[
                AppColors.mint,
                Colors.transparent,
                AppColors.mint,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.backgroundSoft,
              ),
              child: child,
            ),
          ),
        );
      },
      child: const Icon(
        Icons.document_scanner_rounded,
        size: 20,
        color: AppColors.mint,
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onManual,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GlassCard(
        borderColor: AppColors.danger.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.danger,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Không đọc được hoá đơn',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: GradientButton(
                    label: 'Thử lại',
                    icon: Icons.refresh_rounded,
                    height: 46,
                    onPressed: onRetry,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTapScale(
                    onTap: onManual,
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(23),
                        border: Border.all(color: AppColors.outline),
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                      child: const Text(
                        'Nhập thủ công',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 15, color: accent),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _PlainField extends StatelessWidget {
  const _PlainField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final int maxLines;

  /// Gọi khi người dùng tự gõ (không gọi khi giá trị được gán từ code).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: AppColors.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: maxLines,
              onChanged: (_) => onChanged?.call(),
              cursorColor: AppColors.primary,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nhãn nhỏ mô tả một nhóm ứng viên (số tiền / cửa hàng / ngày).
class _CandidateLabel extends StatelessWidget {
  const _CandidateLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _CandidateChip extends StatelessWidget {
  const _CandidateChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AppTapScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.6) : AppColors.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Thẻ trạng thái trợ lý AI on-device (model ngôn ngữ nhỏ chạy offline).
class _AssistantCard extends StatelessWidget {
  const _AssistantCard({
    required this.status,
    required this.progress,
    required this.busy,
    required this.available,
    required this.applied,
    required this.error,
    required this.onEnable,
  });

  final SlmStatus status;
  final double progress;
  final bool busy;
  final bool available;
  final bool applied;
  final String? error;
  final VoidCallback onEnable;

  bool get _failed => status == SlmStatus.failed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        borderColor: _accent.withValues(alpha: 0.28),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(_icon, size: 15, color: _accent),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Trợ lý AI on-device',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                _statusChip(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _description,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            if (status == SlmStatus.downloading) ...<Widget>[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress <= 0 ? null : progress,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Đã tải ${(progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (status == SlmStatus.loading) ...<Widget>[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: const LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: Color(0x14FFFFFF),
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
            if (_failed && error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                error!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.danger,
                  height: 1.45,
                ),
              ),
            ],
            if (!available) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                'Thiết bị này không hỗ trợ engine AI on-device. Kết quả bóc '
                'tách bằng regex vẫn dùng bình thường.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.amber,
                  height: 1.45,
                ),
              ),
            ] else if (status == SlmStatus.notInstalled || _failed) ...<Widget>[
              const SizedBox(height: 14),
              GradientButton(
                label: _failed ? 'Thử lại' : 'Bật trợ lý AI',
                icon: _failed ? Icons.refresh_rounded : Icons.download_rounded,
                height: 44,
                loading: busy,
                onPressed: busy ? null : onEnable,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Màu, icon và mô tả thay đổi theo trạng thái model.
  Color get _accent {
    switch (status) {
      case SlmStatus.ready:
        return AppColors.mint;
      case SlmStatus.failed:
        return AppColors.danger;
      case SlmStatus.downloading:
      case SlmStatus.loading:
        return AppColors.primary;
      case SlmStatus.notInstalled:
        return AppColors.lilac;
    }
  }

  IconData get _icon {
    switch (status) {
      case SlmStatus.ready:
        return Icons.auto_awesome_rounded;
      case SlmStatus.failed:
        return Icons.warning_amber_rounded;
      case SlmStatus.downloading:
        return Icons.download_rounded;
      case SlmStatus.loading:
        return Icons.memory_rounded;
      case SlmStatus.notInstalled:
        return Icons.auto_awesome_outlined;
    }
  }

  String get _description {
    if (!available) {
      return 'Model ngôn ngữ nhỏ (LFM2.5 230M, ~168 MB) chạy hoàn toàn trên '
          'thiết bị, không gửi dữ liệu lên mạng.';
    }
    switch (status) {
      case SlmStatus.notInstalled:
        return 'Bật trợ lý để model đọc lại văn bản OCR và đối chiếu số tiền, '
            'ngày, tên cửa hàng. Model chỉ được chọn trong số ứng viên đã tìm '
            'được nên không thể bịa dữ liệu.';
      case SlmStatus.downloading:
        return 'Đang tải model LFM2.5 230M (~168 MB). Chỉ tải một lần duy '
            'nhất, các lần sau chạy hoàn toàn offline.';
      case SlmStatus.loading:
        return 'Đang nạp model vào bộ nhớ…';
      case SlmStatus.ready:
        return applied
            ? 'Trợ lý đã đối chiếu xong và cập nhật những trường bạn chưa sửa.'
            : 'Trợ lý đã sẵn sàng và đang đối chiếu kết quả bóc tách.';
      case SlmStatus.failed:
        return 'Không khởi động được trợ lý. Kết quả regex bên dưới vẫn dùng '
            'bình thường.';
    }
  }

  Widget _statusChip() {
    final (String text, Color color) = switch (status) {
      SlmStatus.ready => ('Đã bật', AppColors.mint),
      SlmStatus.failed => ('Lỗi', AppColors.danger),
      SlmStatus.downloading => ('Đang tải', AppColors.primary),
      SlmStatus.loading => ('Đang nạp', AppColors.primary),
      SlmStatus.notInstalled => ('Chưa bật', AppColors.textMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.onTap,
    required this.onReset,
  });

  final DateTime date;
  final VoidCallback onTap;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: AppTapScale(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.calendar_month_rounded,
                    size: 17,
                    color: AppColors.lilac,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          AppDateFormatter.date(date),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppDateFormatter.weekdayLong(date),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        AppTapScale(
          onTap: onReset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.outline),
            ),
            child: const Text(
              'Hôm nay',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({required this.selected, required this.onSelected});

  final ExpenseCategory selected;
  final ValueChanged<ExpenseCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: ExpenseCategory.values
          .map(
            (ExpenseCategory category) => _CategoryChip(
              category: category,
              selected: category == selected,
              onTap: () => onSelected(category),
            ),
          )
          .toList(),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppTapScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.medium,
        curve: kAppEmphasisCurve,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? category.gradient : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? category.color.withValues(alpha: 0.7)
                : AppColors.outline,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: category.color.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              category.icon,
              size: 16,
              color: selected ? Colors.black87 : AppColors.textSecondary,
            ),
            const SizedBox(width: 7),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.black87 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RawTextSection extends StatelessWidget {
  const _RawTextSection({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            AppTapScale(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.text_snippet_rounded,
                      size: 17,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Văn bản OCR gốc',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppDurations.medium,
                      curve: kAppEmphasisCurve,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: AppDurations.medium,
              sizeCurve: kAppEmphasisCurve,
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.6,
                    color: AppColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.saving,
    required this.amount,
    required this.onSave,
  });

  final bool saving;
  final String amount;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final double? value = CurrencyFormatter.parseNumber(amount);
    final bool valid = value != null && value > 0;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        decoration: BoxDecoration(
          color: AppColors.backgroundSoft.withValues(alpha: 0.94),
          border: const Border(top: BorderSide(color: AppColors.outline)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Tổng cộng',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 3),
                  AnimatedSwitcher(
                    duration: AppDurations.fast,
                    child: Text(
                      valid
                          ? CurrencyFormatter.currency(value)
                          : '— ₫',
                      key: ValueKey<String>(valid ? '$value' : 'empty'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: valid
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 168,
              child: GradientButton(
                label: 'Lưu chi tiêu',
                icon: Icons.check_rounded,
                height: 52,
                loading: saving,
                gradient: AppGradients.mint,
                foreground: const Color(0xFF04231C),
                onPressed: valid ? onSave : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessOverlay extends StatelessWidget {
  const _SuccessOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: AppDurations.medium,
        curve: kAppCurve,
        builder: (BuildContext context, double value, Widget? child) {
          return ColoredBox(
            color: AppColors.background.withValues(alpha: 0.9 * value),
            child: Opacity(opacity: value, child: child),
          );
        },
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SuccessCheck(size: 104),
              SizedBox(height: 22),
              Text(
                'Đã lưu chi tiêu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chỉ cho nhập số và tự chèn dấu phân cách nghìn.
class _ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final double? value = double.tryParse(digits);
    if (value == null) return oldValue;
    final String formatted = CurrencyFormatter.thousands(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
