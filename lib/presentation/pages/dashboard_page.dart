import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/spending_summary.dart';
import '../providers/expense_provider.dart';
import '../widgets/animated_counter.dart';
import '../widgets/empty_state.dart';
import '../widgets/expense_detail_sheet.dart';
import '../widgets/expense_tile.dart';
import '../widgets/glass_card.dart';
import '../widgets/shimmer_box.dart';
import '../widgets/staggered_entry.dart';

/// Trang chủ: tổng quan tháng + danh sách giao dịch nhóm theo ngày.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onScanRequested});

  final VoidCallback onScanRequested;

  @override
  Widget build(BuildContext context) {
    final ExpenseProvider provider = context.watch<ExpenseProvider>();

    return RefreshIndicator(
      onRefresh: provider.load,
      color: AppColors.mint,
      backgroundColor: AppColors.surfaceHigh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: <Widget>[
          SliverToBoxAdapter(child: _Greeting(provider: provider)),
          SliverToBoxAdapter(child: _MonthlyCard(provider: provider)),
          SliverToBoxAdapter(child: _QuickStats(provider: provider)),
          if (provider.isLoading)
            const SliverToBoxAdapter(child: _LoadingList())
          else if (provider.expenses.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 60),
                child: EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'Chưa có chi tiêu nào',
                  message:
                      'Chụp hoá đơn đầu tiên, ứng dụng sẽ tự đọc số tiền, ngày và tên cửa hàng ngay trên máy.',
                  action: FilledButton.icon(
                    onPressed: onScanRequested,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Quét hoá đơn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            ..._buildGroups(provider),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

  List<Widget> _buildGroups(ExpenseProvider provider) {
    final List<ExpenseDayGroup> groups = provider.groupedByDay;
    final List<Widget> slivers = <Widget>[];
    int index = 0;

    for (final ExpenseDayGroup group in groups) {
      slivers.add(
        SliverToBoxAdapter(
          child: _DayHeader(
            label: AppDateFormatter.dayHeader(group.day),
            total: group.total,
            highlight: index == 0,
          ),
        ),
      );
      slivers.add(
        SliverList.builder(
          itemCount: group.expenses.length,
          itemBuilder: (BuildContext context, int i) {
            final Expense expense = group.expenses[i];
            return StaggeredEntry(
              index: index * 2 + i,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: ExpenseTile(
                  expense: expense,
                  onTap: () => showExpenseDetailSheet(context, expense),
                ),
              ),
            );
          },
        ),
      );
      index++;
      if (index >= 12) break;
    }
    return slivers;
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.provider});

  final ExpenseProvider provider;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _greetingText(now.hour),
                  style: const TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 0.4,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppDateFormatter.weekdayLong(now),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppGradients.glass,
              border: Border.all(color: AppColors.outline),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _greetingText(int hour) {
    if (hour < 11) return 'CHÀO BUỔI SÁNG';
    if (hour < 14) return 'CHÀO BUỔI TRƯA';
    if (hour < 18) return 'CHÀO BUỔI CHIỀU';
    return 'CHÀO BUỔI TỐI';
  }
}

class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard({required this.provider});

  final ExpenseProvider provider;

  @override
  Widget build(BuildContext context) {
    final SpendingSummary summary = provider.monthSummary;
    final double? change = provider.monthChangeRatio;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GlassCard(
        padding: const EdgeInsets.all(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.primary.withValues(alpha: 0.30),
            AppColors.primaryDeep.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        borderColor: AppColors.primary.withValues(alpha: 0.28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'CHI TIÊU ${AppDateFormatter.monthName(DateTime.now()).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedCounter(
              value: summary.total,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                _ChangeBadge(change: change),
                MetaChip(
                  icon: Icons.receipt_outlined,
                  label: '${summary.count} giao dịch',
                ),
                if (summary.count > 0)
                  MetaChip(
                    icon: Icons.trending_up_rounded,
                    label: 'TB ${CurrencyFormatter.compact(summary.average)}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});

  final double? change;

  @override
  Widget build(BuildContext context) {
    final bool up = (change ?? 0) >= 0;
    final Color color = change == null
        ? AppColors.textSecondary
        : (up ? AppColors.amber : AppColors.mint);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            change == null
                ? Icons.remove_rounded
                : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            change == null
                ? 'Chưa có dữ liệu tháng trước'
                : '${(change!.abs() * 100).toStringAsFixed(0)}% so với tháng trước',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.provider});

  final ExpenseProvider provider;

  @override
  Widget build(BuildContext context) {
    final SpendingSummary week = provider.weekSummary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _MiniStat(
              label: 'HÔM NAY',
              value: provider.todayTotal,
              icon: Icons.today_rounded,
              accent: AppColors.mint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MiniStat(
              label: 'TUẦN NÀY',
              value: week.total,
              icon: Icons.calendar_view_week_rounded,
              accent: AppColors.sky,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
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
              Icon(icon, size: 14, color: accent),
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
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.total,
    required this.highlight,
  });

  final String label;
  final double total;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlight ? AppColors.mint : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: highlight ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            CurrencyFormatter.currency(total),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < 4; i++) ...<Widget>[
            const ShimmerBox(height: 70, radius: 18),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
