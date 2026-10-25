import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../domain/entities/spending_summary.dart';
import '../providers/expense_provider.dart';
import '../widgets/animated_counter.dart';
import '../widgets/app_tap_scale.dart';
import '../widgets/category_donut_chart.dart';
import '../widgets/category_visuals.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/staggered_entry.dart';
import '../widgets/weekly_bar_chart.dart';

/// Trang thống kê: donut theo nhóm + bar chart tuần, tất cả vẽ bằng CustomPainter.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late DateTime _month = AppDateFormatter.startOfMonth(DateTime.now());
  int? _selectedSlice;
  int? _selectedDay;

  bool get _canGoNext => _month.isBefore(AppDateFormatter.startOfMonth(DateTime.now()));

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedSlice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ExpenseProvider provider = context.watch<ExpenseProvider>();
    final SpendingSummary summary = provider.summaryForMonth(_month);
    final List<DailyTotal> weekDays =
        SpendingCalculator.dailyTotals(provider.expenses, AppDateFormatter.startOfWeek(DateTime.now()));

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 150),
      children: <Widget>[
        const Text(
          'Thống kê',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Toàn bộ số liệu được tính ngay trên thiết bị',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),
        _MonthSelector(
          month: _month,
          canGoNext: _canGoNext,
          onPrevious: () => _shiftMonth(-1),
          onNext: () => _shiftMonth(1),
        ),
        const SizedBox(height: 16),
        if (summary.total <= 0 && !provider.isLoading)
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 34),
            child: EmptyState(
              icon: Icons.pie_chart_outline_rounded,
              title: 'Tháng này chưa có dữ liệu',
              message:
                  'Chọn tháng khác hoặc quét thêm hoá đơn để xem phân bổ chi tiêu theo nhóm.',
            ),
          )
        else ...<Widget>[
          _OverviewRow(summary: summary, month: _month),
          const SizedBox(height: 14),
          StaggeredEntry(
            index: 0,
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
              child: Column(
                children: <Widget>[
                  const _CardTitle(
                    icon: Icons.donut_large_rounded,
                    title: 'PHÂN BỔ THEO NHÓM',
                  ),
                  const SizedBox(height: 18),
                  CategoryDonutChart(
                    slices: summary.slices,
                    total: summary.total,
                    selectedIndex: _selectedSlice,
                    onSliceSelected: (int? index) =>
                        setState(() => _selectedSlice = index),
                  ),
                  const SizedBox(height: 18),
                  for (int i = 0; i < summary.slices.length; i++)
                    StaggeredEntry(
                      index: i,
                      child: _LegendRow(
                        slice: summary.slices[i],
                        selected: _selectedSlice == i,
                        dimmed: _selectedSlice != null && _selectedSlice != i,
                        onTap: () => setState(
                          () => _selectedSlice = _selectedSlice == i ? null : i,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const _CardTitle(
                      icon: Icons.bar_chart_rounded,
                      title: 'CHI TIÊU TRONG TUẦN',
                    ),
                    const Spacer(),
                    Text(
                      '${CurrencyFormatter.compact(weekDays.fold<double>(0, (double s, DailyTotal d) => s + d.amount))} ₫',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.mint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                WeeklyBarChart(
                  days: weekDays,
                  highlightedIndex: _selectedDay,
                  onBarTap: (int index) => setState(
                    () => _selectedDay = _selectedDay == index ? null : index,
                  ),
                ),
                const SizedBox(height: 6),
                _SelectedDayInfo(
                  days: weekDays,
                  index: _selectedDay ??
                      (weekDays.indexWhere(
                        (DailyTotal day) =>
                            AppDateFormatter.isSameDay(day.date, DateTime.now()),
                      )),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.month,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      radius: AppRadius.md,
      child: Row(
        children: <Widget>[
          _NavButton(icon: Icons.chevron_left_rounded, onTap: onPrevious),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppDurations.medium,
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                AppDateFormatter.monthName(month),
                key: ValueKey<String>('${month.year}-${month.month}'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          _NavButton(
            icon: Icons.chevron_right_rounded,
            onTap: canGoNext ? onNext : null,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return AppTapScale(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 22,
          color: enabled ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({required this.summary, required this.month});

  final SpendingSummary summary;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final int daysElapsed = month.month == DateTime.now().month &&
            month.year == DateTime.now().year
        ? DateTime.now().day
        : AppDateFormatter.endOfMonth(month).day;
    final double perDay = daysElapsed == 0 ? 0 : summary.total / daysElapsed;

    return Row(
      children: <Widget>[
        Expanded(
          child: _StatPill(
            label: 'TỔNG',
            value: summary.total,
            icon: Icons.savings_rounded,
            accent: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatPill(
            label: 'TB/NGÀY',
            value: perDay,
            icon: Icons.timelapse_rounded,
            accent: AppColors.mint,
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final double value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedCounter(
            value: value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final CategorySlice slice;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AppDurations.fast,
      opacity: dimmed ? 0.45 : 1,
      child: AppTapScale(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: slice.category.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    slice.category.icon,
                    size: 14,
                    color: slice.category.color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    slice.category.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${slice.count} giao dịch',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(slice.share * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: slice.category.color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.currency(slice.amount),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              _ShareBar(
                share: slice.share,
                color: slice.category.color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.share, required this.color});

  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 5,
        color: Colors.white.withValues(alpha: 0.05),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: share.clamp(0, 1)),
          duration: const Duration(milliseconds: 800),
          curve: kAppEmphasisCurve,
          builder: (BuildContext context, double value, Widget? _) =>
              FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    color,
                    color.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedDayInfo extends StatelessWidget {
  const _SelectedDayInfo({required this.days, required this.index});

  final List<DailyTotal> days;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (index < 0 || index >= days.length) return const SizedBox.shrink();
    final DailyTotal day = days[index];
    return Row(
      children: <Widget>[
        Icon(
          Icons.circle,
          size: 7,
          color: AppDateFormatter.isSameDay(day.date, DateTime.now())
              ? AppColors.mint
              : AppColors.textMuted,
        ),
        const SizedBox(width: 8),
        Text(
          '${AppDateFormatter.weekdayLong(day.date)} • ${AppDateFormatter.date(day.date)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Text(
          day.amount <= 0 ? 'Không phát sinh' : CurrencyFormatter.currency(day.amount),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: day.amount <= 0 ? AppColors.textMuted : AppColors.mint,
          ),
        ),
      ],
    );
  }
}
