import 'package:flutter/material.dart';

import '../../core/navigation/page_transitions.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_tap_scale.dart';
import 'dashboard_page.dart';
import 'scanner_page.dart';
import 'stats_page.dart';

/// Khung chính: 2 tab (icon-only) + nút quét gradient ở giữa.
class HomeShellPage extends StatefulWidget {
  const HomeShellPage({super.key});

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  int _index = 0;

  Future<void> _openScanner() async {
    await Navigator.of(context).push<bool>(slideUpRoute(const ScannerPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.scene),
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: <Widget>[
              DashboardPage(onScanRequested: _openScanner),
              const StatsPage(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTabSelected: (int value) => setState(() => _index = value),
        onScanPressed: _openScanner,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.onTabSelected,
    required this.onScanPressed,
  });

  final int index;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onScanPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: AppColors.outline),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _NavItem(
                  icon: Icons.dashboard_rounded,
                  active: index == 0,
                  onTap: () => onTabSelected(0),
                  tooltip: 'Chi tiêu',
                ),
              ),
              const SizedBox(width: 8),
              _ScanButton(onTap: onScanPressed),
              const SizedBox(width: 8),
              Expanded(
                child: _NavItem(
                  icon: Icons.insights_rounded,
                  active: index == 1,
                  onTap: () => onTabSelected(1),
                  tooltip: 'Thống kê',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AppTapScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: kAppEmphasisCurve,
          height: 52,
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(
                    colors: <Color>[
                      AppColors.primary.withValues(alpha: 0.26),
                      AppColors.primary.withValues(alpha: 0.06),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.42)
                  : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size: 23,
            color: active ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ScanButton extends StatefulWidget {
  const _ScanButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTapScale(
      onTap: widget.onTap,
      scale: 0.94,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double value = _controller.value;
          return Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppGradients.primary,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30 + value * 0.25),
                  blurRadius: 18 + value * 12,
                  spreadRadius: 1 + value * 3,
                ),
              ],
            ),
            child: child,
          );
        },
        child: const Icon(
          Icons.qr_code_scanner_rounded,
          size: 27,
          color: Colors.white,
        ),
      ),
    );
  }
}
