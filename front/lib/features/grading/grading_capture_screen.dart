import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/app_error_toast.dart';

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
  Size? _lastBoxSize;

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
    // frame_hint 계산이 portrait 가정에 의존 — capture 동안 portrait 고정.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    _initCamera();
  }

  @override
  void dispose() {
    _focusRingTimer?.cancel();
    _frameStateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
      final shotFile = File(xfile.path);

      setState(() => _frameState = _FrameState.complete);
      _frameStateTimer?.cancel();
      _frameStateTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _frameState = _FrameState.basic);
      });

      final side = _step == 0 ? 'front' : 'back';
      final precheck = await _runPrecheck(shotFile, side);
      if (!mounted) return;
      if (precheck != null && precheck['ok'] != true) {
        try { if (shotFile.existsSync()) shotFile.deleteSync(); } catch (_) {}
        final title = (precheck['reason_title'] as String?) ?? '다시 촬영해 주세요';
        final msg = (precheck['reason_message'] as String?) ?? '';
        setState(() => _isCapturing = false);
        AppErrorToast.show(context, msg.isNotEmpty ? '$title · $msg' : title);
        return;
      }

      _photos.add(shotFile);

      if (_step < 1) {
        if (mounted) {
          setState(() { _step++; _isCapturing = false; });
          AppInfoToast.show(context, '앞면 촬영 완료 · 이제 뒷면을 촬영해 주세요');
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
        AppErrorToast.show(context, '촬영 실패: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> _runPrecheck(File file, String side) async {
    try {
      final frameRect = _normalizedFrameRect();
      final res = await ApiClient.postMultipart(
        ApiConstants.gradingPrecheck,
        files: {'image': file},
        fields: {
          'side': side,
          'frame_x': (frameRect['frame_x'] ?? 0).toString(),
          'frame_y': (frameRect['frame_y'] ?? 0).toString(),
          'frame_w': (frameRect['frame_w'] ?? 1).toString(),
          'frame_h': (frameRect['frame_h'] ?? 1).toString(),
        },
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      );
      final data = res['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  // Flutter capture frame → sensor 좌표계로 변환된 normalized frame_hint.
  // 화면 좌표 기반 hardcoded fallback (sensor BoxFit.cover crop 무시) — 안전망.
  static const _frameDefaultX = 0.175;
  static const _frameDefaultY = 0.046;
  static const _frameDefaultW = 0.65;
  static const _frameDefaultH = 0.908;

  Map<String, double> _defaultFrameRect() => {
        'frame_x': _frameDefaultX,
        'frame_y': _frameDefaultY,
        'frame_w': _frameDefaultW,
        'frame_h': _frameDefaultH,
      };

  // sensor BoxFit.cover crop 을 반영한 frame_hint 산출.
  // _FrameOverlayPainter 의 box 좌표 frame 을 sensor 이미지 (takePicture 결과)
  // 의 normalized 0~1 좌표로 변환.
  //
  // 가정:
  //   1. capture screen 은 portrait 고정.
  //   2. controller.previewSize 는 sensor raw (보통 landscape).
  //   3. takePicture() 결과 이미지는 portrait orientation 으로 저장됨.
  //
  // 방어적 처리:
  //   - previewSize.width/height 의 의미가 device/플러그인마다 다를 수 있어
  //     long/short 으로 통합 후 portrait 가정에서 swap.
  //   - 결과 frame aspect 가 카드 비율 (63/88 ≈ 0.716) 에서 크게 벗어나면
  //     fallback (sensor aspect 추론 실패 시).
  Map<String, double> _normalizedFrameRect([CameraController? c, Size? boxSize]) {
    c ??= _controller;
    boxSize ??= _lastBoxSize;
    if (c == null || boxSize == null || boxSize.width <= 0 || boxSize.height <= 0) {
      return _defaultFrameRect();
    }

    final preview = c.value.previewSize;
    if (preview == null || preview.width <= 0 || preview.height <= 0) {
      return _defaultFrameRect();
    }

    // sensor long/short 으로 통합 (orientation 의미 디바이스/플러그인 차이 흡수).
    final sensorLong = preview.width >= preview.height ? preview.width : preview.height;
    final sensorShort = preview.width >= preview.height ? preview.height : preview.width;

    // portrait 고정 가정: 이미지 width = sensor short, height = sensor long.
    final sensorW = sensorShort;
    final sensorH = sensorLong;
    final sensorAspect = sensorW / sensorH; // < 1 (portrait)
    final boxAspect = boxSize.width / boxSize.height; // < 1 on phone portrait

    // BoxFit.cover: sensor 를 box 에 cover.
    double scaledSensorW;
    double scaledSensorH;
    if (sensorAspect > boxAspect) {
      // sensor 가 box 보다 가로로 wide → height 가 fit, 좌우 crop.
      scaledSensorH = boxSize.height;
      scaledSensorW = boxSize.height * sensorAspect;
    } else {
      // sensor 가 box 보다 narrow → width 가 fit, 상하 crop.
      scaledSensorW = boxSize.width;
      scaledSensorH = boxSize.width / sensorAspect;
    }

    // _FrameOverlayPainter 와 동일한 box 좌표 frame.
    final framePixelW = boxSize.width * _frameWidthRatio;
    final framePixelH = framePixelW / _frameAspect;
    final framePixelX = (boxSize.width - framePixelW) / 2.0;
    final framePixelY = (boxSize.height - framePixelH) / 2.0;

    // scaledSensor 의 box 안 offset (BoxFit.cover 의 crop 보정).
    final scaledOffsetX = (boxSize.width - scaledSensorW) / 2.0;
    final scaledOffsetY = (boxSize.height - scaledSensorH) / 2.0;

    // frame in scaledSensor 좌표.
    final frameInSensorX = framePixelX - scaledOffsetX;
    final frameInSensorY = framePixelY - scaledOffsetY;

    final frameNormX = (frameInSensorX / scaledSensorW).clamp(0.0, 1.0);
    final frameNormY = (frameInSensorY / scaledSensorH).clamp(0.0, 1.0);
    final frameNormW = (framePixelW / scaledSensorW).clamp(0.0, 1.0);
    final frameNormH = (framePixelH / scaledSensorH).clamp(0.0, 1.0);

    // 결과 sensor-aspect 검증 — 카드 비율 (~0.716) 에서 0.60~0.85 벗어나면 fallback.
    // backend P0-C gate (0.62~0.82) 보다 살짝 넓혀 잘못된 hint 가 gate 까지 도달 X.
    final resultAspect = (frameNormW * sensorW) / (frameNormH * sensorH);
    final invalid =
        resultAspect.isNaN || resultAspect < 0.60 || resultAspect > 0.85;

    if (kDebugMode) {
      debugPrint('[frame_hint] preview=$preview box=$boxSize '
          'sensorAspect=${sensorAspect.toStringAsFixed(3)} '
          'boxAspect=${boxAspect.toStringAsFixed(3)} '
          'scaled=(${scaledSensorW.toStringAsFixed(0)},${scaledSensorH.toStringAsFixed(0)}) '
          'frame=(${frameNormX.toStringAsFixed(3)},${frameNormY.toStringAsFixed(3)},'
          '${frameNormW.toStringAsFixed(3)},${frameNormH.toStringAsFixed(3)}) '
          'aspect=${resultAspect.toStringAsFixed(3)}'
          '${invalid ? " INVALID→fallback" : ""}');
    }

    if (invalid) {
      return _defaultFrameRect();
    }

    return {
      'frame_x': frameNormX,
      'frame_y': frameNormY,
      'frame_w': frameNormW,
      'frame_h': frameNormH,
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
        _lastBoxSize = boxSize;
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
