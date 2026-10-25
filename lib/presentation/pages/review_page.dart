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

  @override
  void initState() {
    super.initState();
    _session = context.read<ScanSessionController>();
    _session.addListener(_syncFromSession);
    _syncFromSession();
  }

  @override
  void dispose() {
    _session.removeListener(_syncFromSession);
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    _merchantFocus.dispose();
    super.dispose();
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

  // ---------------------------------------------------------------------------
  // Hành động
  // ---------------------------------------------------------------------------

  void _useCandidate(double value) {
    setState(() {
      _amount.text = CurrencyFormatter.thousands(value);
      _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
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
    if (picked != null && mounted) setState(() => _date = picked);
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
                            const StaggeredEntry(
                              index: 1,
                              child: _RecognizingSkeleton(),
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
    final List<double> candidates = session.parsed.amountCandidates;

    return <Widget>[
      StaggeredEntry(
        index: 2,
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
                      onChanged: (_) => setState(() {}),
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
                const Text(
                  'Số tiền tìm thấy trên hoá đơn',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: candidates
                      .take(4)
                      .map(
                        (double value) => _CandidateChip(
                          label: CurrencyFormatter.thousands(value),
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
        index: 3,
        child: _SectionCard(
          title: 'Cửa hàng',
          icon: Icons.storefront_rounded,
          accent: AppColors.sky,
          child: _PlainField(
            controller: _merchant,
            focusNode: _merchantFocus,
            hint: 'Tên cửa hàng / nơi chi tiêu',
            icon: Icons.edit_rounded,
          ),
        ),
      ),
      StaggeredEntry(
        index: 4,
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
                onReset: () => setState(() => _date = DateTime.now()),
              ),
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
        index: 5,
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
      if (session.parsed.rawText.trim().isNotEmpty)
        StaggeredEntry(
          index: 6,
          child: _RawTextSection(
            text: session.parsed.rawText,
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

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.imagePath, required this.fallbackPath});

  final String? imagePath;
  final String fallbackPath;

  @override
  Widget build(BuildContext context) {
    final String path = imagePath ?? fallbackPath;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          height: 216,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              AnimatedSwitcher(
                duration: AppDurations.medium,
                child: Image.file(
                  File(path),
                  key: ValueKey<String>(path),
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
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
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.crop_rounded,
                        size: 13,
                        color: AppColors.mint,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Ảnh hoá đơn đã cắt',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecognizingSkeleton extends StatelessWidget {
  const _RecognizingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        GlassCard(
          child: Row(
            children: <Widget>[
              const _SpinningChip(),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Đang nhận dạng văn bản…',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'ML Kit xử lý ngay trên thiết bị, không cần mạng.',
                      style: TextStyle(
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
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final int maxLines;

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

class _CandidateChip extends StatelessWidget {
  const _CandidateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppTapScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.mint.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.mint.withValues(alpha: 0.6)
                : AppColors.outline,
          ),
        ),
        child: Text(
          '$label ₫',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.mint : AppColors.textSecondary,
          ),
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
