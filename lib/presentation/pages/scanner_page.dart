import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/page_transitions.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/normalized_rect.dart';
import '../widgets/expense_tile.dart';
import '../widgets/scan_frame_overlay.dart';
import 'review_page.dart';

/// Màn hình camera: ngắm khung, bật/tắt đèn, chạm để lấy nét, chụp hoá đơn.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const NormalizedRect _cropFrame = NormalizedRect.receiptFrame;

  CameraController? _controller;
  bool _initializing = true;
  String? _errorMessage;
  FlashMode _flashMode = FlashMode.off;
  bool _capturing = false;
  Offset? _focusPoint;

  late final AnimationController _scanBeam = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  late final AnimationController _focusRing = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanBeam.repeat(reverse: true);
    _bootstrapCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanBeam.dispose();
    _focusRing.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _controller;
    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed &&
        controller == null &&
        mounted) {
      _bootstrapCamera();
    }
  }

  Future<void> _bootstrapCamera() async {
    setState(() {
      _initializing = true;
      _errorMessage = null;
    });

    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'Thiết bị không có camera.');
      }
      final CameraDescription description = cameras.firstWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final CameraController controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(_flashMode);

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.description ?? error.code;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$error';
        _initializing = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Tương tác camera
  // ---------------------------------------------------------------------------

  Future<void> _cycleFlash() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final FlashMode next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };

    try {
      await controller.setFlashMode(next);
      if (!mounted) return;
      setState(() => _flashMode = next);
    } on CameraException catch (error) {
      _showMessage('Không đổi được chế độ đèn: ${error.code}');
    }
  }

  Future<void> _handleTapToFocus(TapUpDetails details, Rect previewRect) async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final Offset position = details.localPosition;
    if (!previewRect.contains(position)) return;

    setState(() => _focusPoint = position);
    _focusRing.forward(from: 0);

    try {
      await controller.setFocusPoint(
        Offset(
          ((position.dx - previewRect.left) / previewRect.width).clamp(0.0, 1.0),
          ((position.dy - previewRect.top) / previewRect.height).clamp(0.0, 1.0),
        ),
      );
    } on CameraException {
      // Một số thiết bị không hỗ trợ lấy nét theo điểm - bỏ qua.
    }
  }

  Future<void> _capture() async {
    final CameraController? controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing) {
      return;
    }

    setState(() => _capturing = true);
    try {
      final XFile file = await controller.takePicture();
      if (!mounted) return;
      final bool? saved = await Navigator.of(context).push<bool>(
        fadeScaleRoute(
          ReviewPage(imagePath: file.path, crop: _cropFrame),
        ),
      );
      if (!mounted) return;
      // Lưu xong thì đóng luôn màn camera để về trang chính.
      if (saved == true) {
        Navigator.of(context).pop(true);
      }
    } on CameraException catch (error) {
      _showMessage('Không chụp được: ${error.description ?? error.code}');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surfaceHigh,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size screen = constraints.biggest;
          final CameraController? controller = _controller;
          final double aspect = controller == null
              ? 9 / 16
              : _previewAspectRatio(controller);
          final Rect previewRect = _fitCenter(screen, aspect);
          final Rect cropRect = Rect.fromLTWH(
            previewRect.left + _cropFrame.left * previewRect.width,
            previewRect.top + _cropFrame.top * previewRect.height,
            _cropFrame.width * previewRect.width,
            _cropFrame.height * previewRect.height,
          );

          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: _buildPreview(controller, previewRect),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (TapUpDetails details) =>
                      _handleTapToFocus(details, previewRect),
                  child: AnimatedBuilder(
                    animation: _scanBeam,
                    builder: (BuildContext context, Widget? _) => ScanFrameOverlay(
                      frame: cropRect,
                      scanProgress: _scanBeam.value,
                    ),
                  ),
                ),
              ),
              if (_focusPoint != null)
                _FocusRing(
                  position: _focusPoint!,
                  animation: _focusRing,
                ),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    _TopBar(
                      flashMode: _flashMode,
                      onFlashTap: _cycleFlash,
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    _BottomControls(
                      capturing: _capturing,
                      enabled: controller?.value.isInitialized ?? false,
                      onCapture: _capture,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPreview(CameraController? controller, Rect previewRect) {
    if (_initializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CircularProgressIndicator(
              color: AppColors.mint,
              strokeWidth: 2.4,
            ),
            SizedBox(height: 16),
            Text(
              'Đang khởi động camera…',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null || controller == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.no_photography_outlined,
                size: 46,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 16),
              const Text(
                'Không mở được camera',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Vui lòng cấp quyền camera trong cài đặt.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _bootstrapCamera,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Thử lại'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: SizedBox(
        width: previewRect.width,
        height: previewRect.height,
        child: CameraPreview(controller),
      ),
    );
  }

  /// Aspect ratio hiển thị của preview (CameraPreview tự xoay theo hướng thiết bị).
  double _previewAspectRatio(CameraController controller) {
    final CameraValue value = controller.value;
    final DeviceOrientation orientation = value.lockedCaptureOrientation ??
        value.deviceOrientation;
    final bool landscape =
        orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
    final double aspect = value.aspectRatio;
    if (aspect <= 0) return 9 / 16;
    return landscape ? aspect : 1 / aspect;
  }

  /// Vùng hiển thị preview canh giữa trong màn hình, giữ đúng tỉ lệ cảm biến.
  Rect _fitCenter(Size outer, double aspect) {
    final double width = outer.width;
    final double height = width / aspect;
    if (height <= outer.height) {
      return Rect.fromLTWH(0, (outer.height - height) / 2, width, height);
    }
    final double fittedHeight = outer.height;
    final double fittedWidth = fittedHeight * aspect;
    return Rect.fromLTWH(
      (outer.width - fittedWidth) / 2,
      0,
      fittedWidth,
      fittedHeight,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.flashMode,
    required this.onFlashTap,
    required this.onClose,
  });

  final FlashMode flashMode;
  final VoidCallback onFlashTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: <Widget>[
          CircleIconButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            tooltip: 'Đóng',
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.memory_rounded,
                  size: 14,
                  color: AppColors.mint,
                ),
                const SizedBox(width: 7),
                const Text(
                  'OCR on-device',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: AppDurations.fast,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                ScaleTransition(scale: animation, child: child),
            child: CircleIconButton(
              key: ValueKey<FlashMode>(flashMode),
              icon: switch (flashMode) {
                FlashMode.auto => Icons.flash_auto_rounded,
                FlashMode.always || FlashMode.torch => Icons.flash_on_rounded,
                _ => Icons.flash_off_rounded,
              },
              active: flashMode != FlashMode.off,
              onTap: onFlashTap,
              tooltip: 'Chế độ đèn',
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.capturing,
    required this.enabled,
    required this.onCapture,
  });

  final bool capturing;
  final bool enabled;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.46),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Đặt hoá đơn nằm gọn trong khung',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _ShutterButton(
            capturing: capturing,
            enabled: enabled,
            onTap: onCapture,
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatefulWidget {
  const _ShutterButton({
    required this.capturing,
    required this.enabled,
    required this.onTap,
  });

  final bool capturing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled && !widget.capturing ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (BuildContext context, Widget? child) {
          return Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 3,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.mint
                      .withValues(alpha: 0.16 + _pulse.value * 0.16),
                  blurRadius: 22 + _pulse.value * 14,
                  spreadRadius: 2 + _pulse.value * 3,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: AnimatedScale(
                duration: AppDurations.fast,
                scale: widget.capturing ? 0.78 : 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.capturing
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[Color(0xFF39E8BE), Color(0xFF14A98A)],
                          ),
                    color: widget.capturing ? Colors.white24 : null,
                  ),
                  child: widget.capturing
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FocusRing extends StatelessWidget {
  const _FocusRing({required this.position, required this.animation});

  final Offset position;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    const double size = 74;
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, Widget? _) {
            final double value = animation.value;
            final double scale = 0.6 + kAppEmphasisCurve.transform(value) * 0.5;
            final double opacity = (1 - value).clamp(0.0, 1.0) * 0.9 +
                (animation.isCompleted ? 0 : 0.3);
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.mint, width: 1.6),
                  ),
                  child: Center(
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.mint,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
