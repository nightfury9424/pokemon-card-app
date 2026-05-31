import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

enum _FrameState { basic, focusing, capturing, complete }

class GradingCaptureScreen extends StatefulWidget {
  final String? assetId;
  final String? cardId;
  final String? cardName;
  const GradingCaptureScreen({super.key, this.assetId, this.cardId, this.cardName});

  @override
  State<GradingCaptureScreen> createState() => _GradingCaptureScreenState();
}

class _GradingCaptureScreenState extends State<GradingCaptureScreen>
    with WidgetsBindingObserver {
  static const _frameAspect = 63.0 / 88.0;
  static const _frameWidthRatio = 0.65;

  CameraController? _controller;
  Future<void>? _initFuture;
  int _step = 0;
  final List<File> _photos = [];
  bool _isCapturing = false;
  String? _initError;
  _FrameState _frameState = _FrameState.basic;
  Offset? _focusPoint;
  Timer? _focusRingTimer;
  Timer? _frameStateTimer;

  static const _stepLabels = [
    ('앞면 촬영', '카드 4개 모서리가 프레임 안에 모두 보이도록 맞춘 뒤 촬영해 주세요'),
    ('뒷면 촬영', '카드 4개 모서리가 프레임 안에 모두 보이도록 맞춘 뒤 촬영해 주세요'),
  ];

  static const _guideHints = [
    '카드와 카메라 사이 15cm 이상 거리를 두면 더 선명해요',
    '화면 가운데를 탭하면 초점을 맞출 수 있어요',
    '손가락이나 그림자가 카드 위에 들어가지 않게 해주세요',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    _focusRingTimer?.cancel();
    _frameStateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      _initFuture = controller.initialize();
      await _initFuture;
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  /// BoxFit.cover crop 보정 — preview aspect vs box aspect 비교 후 sensor 좌표로 변환.
  Offset _tapToSensorPoint(Offset tap, Size boxSize, double previewW, double previewH) {
    final boxAspect = boxSize.width / boxSize.height;
    final previewAspect = previewW / previewH;
    double scaledW, scaledH;
    if (previewAspect > boxAspect) {
      scaledH = boxSize.height;
      scaledW = boxSize.height * previewAspect;
    } else {
      scaledW = boxSize.width;
      scaledH = boxSize.width / previewAspect;
    }
    final offsetX = (scaledW - boxSize.width) / 2.0;
    final offsetY = (scaledH - boxSize.height) / 2.0;
    final sensorX = ((tap.dx + offsetX) / scaledW).clamp(0.0, 1.0);
    final sensorY = ((tap.dy + offsetY) / scaledH).clamp(0.0, 1.0);
    return Offset(sensorX, sensorY);
  }

  Future<void> _tapToFocus(TapDownDetails details, Size boxSize, double previewW, double previewH) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final tap = details.localPosition;
    final sensor = _tapToSensorPoint(tap, boxSize, previewW, previewH);
    setState(() {
      _focusPoint = tap;
      _frameState = _FrameState.focusing;
    });
    _focusRingTimer?.cancel();
    _focusRingTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    _frameStateTimer?.cancel();
    _frameStateTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() {
        if (_frameState == _FrameState.focusing) _frameState = _FrameState.basic;
      });
    });
    try {
      await c.setFocusPoint(sensor);
      await c.setExposurePoint(sensor);
    } catch (_) {}
  }

  Future<void> _shutter() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isCapturing) return;
    setState(() {
      _isCapturing = true;
      _frameState = _FrameState.capturing;
    });
    try {
      await Future.delayed(const Duration(milliseconds: 350));
      final xfile = await c.takePicture();
      _photos.add(File(xfile.path));

      setState(() => _frameState = _FrameState.complete);
      _frameStateTimer?.cancel();
      _frameStateTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _frameState = _FrameState.basic);
      });

      if (_step < 1) {
        if (mounted) {
          setState(() { _step++; _isCapturing = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('앞면 촬영 완료 · 이제 뒷면을 촬영해 주세요'),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFF1A3A6A),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isCapturing = false);
          final frameRect = _normalizedFrameRect();
          final result = await context.push<dynamic>('/grading/result', extra: {
            'photos': List<File>.from(_photos),
            'assetId': widget.assetId,
            'cardId': widget.cardId,
            'cardName': widget.cardName,
            'frameRect': frameRect,
          });
          if (!mounted) return;
          if (result == 'retake') {
            setState(() {
              _step = 0;
              _photos.clear();
              _frameState = _FrameState.basic;
            });
          } else if (result == true) {
            context.pop(true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _frameState = _FrameState.basic;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('촬영 실패: $e')),
        );
      }
    }
  }

  Map<String, double> _normalizedFrameRect() {
    final frameW = _frameWidthRatio;
    final frameH = (_frameWidthRatio / _frameAspect).clamp(0.0, 1.0);
    final frameX = (1.0 - frameW) / 2.0;
    final frameY = (1.0 - frameH) / 2.0;
    return {
      'frame_x': frameX,
      'frame_y': frameY,
      'frame_w': frameW,
      'frame_h': frameH,
    };
  }

  @override
  Widget build(BuildContext context) {
    final (label, hint) = _stepLabels[_step];
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_initError != null)
              _buildError(_initError!)
            else if (!ready)
              const Center(child: CircularProgressIndicator(color: AppColors.blue))
            else
              _buildPreviewWithFrame(c),
            _buildTopBar(),
            _buildBottomBar(label, hint, ready),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          const Text('카메라를 열 수 없어요',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          Text(msg,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _buildPreviewWithFrame(CameraController c) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = c.value.previewSize;
        final previewW = size?.height ?? 1080.0;
        final previewH = size?.width ?? 1920.0;
        final boxSize = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _tapToFocus(d, boxSize, previewW, previewH),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: previewW,
                    height: previewH,
                    child: CameraPreview(c),
                  ),
                ),
              ),
              CustomPaint(
                size: boxSize,
                painter: _FrameOverlayPainter(
                  frameAspect: _frameAspect,
                  frameWidthRatio: _frameWidthRatio,
                  state: _frameState,
                ),
              ),
              if (_focusPoint != null)
                Positioned(
                  left: _focusPoint!.dx - 32,
                  top: _focusPoint!.dy - 32,
                  child: IgnorePointer(
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFD700), width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: (_step + 1) / 2,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(AppColors.blue),
            ),
          ),
          const SizedBox(width: 8),
          Text('${_step + 1}/2',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(width: 8),
        ]),
      ),
    );
  }

  Widget _buildBottomBar(String label, String hint, bool ready) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(hint,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('💡 ${_guideHints[_step % _guideHints.length]}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: ready && !_isCapturing ? _shutter : null,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: _isCapturing ? 0.4 : 1.0),
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: _isCapturing
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                            color: AppColors.blue, strokeWidth: 3),
                      )
                    : const Icon(Icons.camera_alt,
                        size: 32, color: AppColors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameOverlayPainter extends CustomPainter {
  final double frameAspect;
  final double frameWidthRatio;
  final _FrameState state;
  _FrameOverlayPainter({
    required this.frameAspect,
    required this.frameWidthRatio,
    required this.state,
  });

  Color get _strokeColor {
    switch (state) {
      case _FrameState.focusing:  return const Color(0xFFFFD700);
      case _FrameState.capturing: return const Color(0xFF60A5FA);
      case _FrameState.complete:  return const Color(0xFF10B981);
      case _FrameState.basic:     return Colors.white;
    }
  }

  Color get _markerColor {
    switch (state) {
      case _FrameState.focusing:  return const Color(0xFFFFD700);
      case _FrameState.capturing: return const Color(0xFF60A5FA);
      case _FrameState.complete:  return const Color(0xFF10B981);
      case _FrameState.basic:     return AppColors.blue;
    }
  }

  double get _glowAlpha {
    switch (state) {
      case _FrameState.focusing:  return 0.6;
      case _FrameState.capturing: return 0.5;
      case _FrameState.complete:  return 0.8;
      case _FrameState.basic:     return 0.0;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frameW = size.width * frameWidthRatio;
    final frameH = (frameW / frameAspect).clamp(0.0, size.height * 0.85);
    final fLeft = (size.width - frameW) / 2.0;
    final fTop = (size.height - frameH) / 2.0;
    final rect = Rect.fromLTWH(fLeft, fTop, frameW, frameH);

    final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)));
    canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), dim);

    if (_glowAlpha > 0) {
      final glow = Paint()
        ..color = _strokeColor.withValues(alpha: _glowAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(14)), glow);
    }

    final framePaint = Paint()
      ..color = _strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = state == _FrameState.basic ? 2 : 3;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)), framePaint);

    final markerPaint = Paint()
      ..color = _markerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const markerLen = 22.0;
    for (final corner in [
      Offset(fLeft, fTop),
      Offset(fLeft + frameW, fTop),
      Offset(fLeft, fTop + frameH),
      Offset(fLeft + frameW, fTop + frameH),
    ]) {
      final dx = corner.dx < size.width / 2 ? 1.0 : -1.0;
      final dy = corner.dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawLine(corner, Offset(corner.dx + dx * markerLen, corner.dy),
          markerPaint);
      canvas.drawLine(corner, Offset(corner.dx, corner.dy + dy * markerLen),
          markerPaint);
    }

    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cx = fLeft + frameW / 2;
    final cy = fTop + frameH / 2;
    canvas.drawLine(Offset(cx - 16, cy), Offset(cx + 16, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - 16), Offset(cx, cy + 16), crossPaint);
  }

  @override
  bool shouldRepaint(covariant _FrameOverlayPainter old) =>
      old.state != state;
}
