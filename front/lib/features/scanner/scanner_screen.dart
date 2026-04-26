import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);

  bool _isProcessing = false;
  bool _cameraReady = false;
  String _statusText = '카드를 화면에 보여주세요';
  String? _detectedNumber;
  DateTime _lastScanTime = DateTime.fromMillisecondsSinceEpoch(0);

  static final _numberPattern = RegExp(r'(\d{2,4})[/\\](\d{2,4})');

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _statusText = '카메라 권한이 필요합니다');
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    setState(() => _cameraReady = true);
    _startScanning();
  }

  void _startScanning() {
    _cameraController?.startImageStream((image) async {
      if (_isProcessing) return;
      final now = DateTime.now();
      if (now.difference(_lastScanTime).inMilliseconds < 800) return;
      _isProcessing = true;
      _lastScanTime = now;

      try {
        final inputImage = _buildInputImage(image);
        final recognized = await _textRecognizer.processImage(inputImage);
        final number = _extractCardNumber(recognized.text);

        if (number != null && number != _detectedNumber) {
          _detectedNumber = number;
          await _lookupCard(number);
        }
      } finally {
        _isProcessing = false;
      }
    });
  }

  InputImage _buildInputImage(CameraImage image) {
    final bytes = image.planes.fold<List<int>>(
      [],
      (buffer, plane) => buffer..addAll(plane.bytes),
    );
    return InputImage.fromBytes(
      bytes: Uint8List.fromList(bytes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  String? _extractCardNumber(String text) {
    final match = _numberPattern.firstMatch(text);
    return match?.group(0);
  }

  Future<void> _lookupCard(String number) async {
    if (!mounted) return;
    setState(() => _statusText = '카드 조회 중... ($number)');

    try {
      final response = await ApiClient.get(
        ApiConstants.cards,
        params: {'number': number, 'language': 'KO'},
      );

      final items = response['data'] as List?;
      if (items == null || items.isEmpty) {
        setState(() {
          _statusText = '카드를 찾을 수 없습니다 ($number)';
          _detectedNumber = null;
        });
        return;
      }

      if (!mounted) return;
      await _cameraController?.stopImageStream();

      final card = items.first;
      context.push('/card/${card['cardId']}', extra: card);
    } catch (e) {
      setState(() {
        _statusText = '조회 실패: $e';
        _detectedNumber = null;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('카드 스캔'),
      ),
      body: Stack(
        children: [
          // 카메라 프리뷰
          if (_cameraReady && _cameraController != null)
            Positioned.fill(child: CameraPreview(_cameraController!)),

          // 가이드 오버레이
          Positioned.fill(child: _buildGuideOverlay()),

          // 상태 텍스트
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideOverlay() {
    return CustomPaint(painter: _GuideBoxPainter());
  }
}

class _GuideBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boxH = size.height * 0.65;
    final boxW = boxH / 1.396;
    final left = (size.width - boxW) / 2;
    final top = (size.height - boxH) / 2;
    final rect = Rect.fromLTWH(left, top, boxW, boxH);

    // 어두운 배경
    final bgPaint = Paint()..color = Colors.black45;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    canvas.drawRect(rect, Paint()..blendMode = BlendMode.clear);

    // 가이드 박스 테두리
    final borderPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), borderPaint);

    // 코너 강조
    final cornerPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 20.0;

    // 좌상단
    canvas.drawLine(Offset(left, top + len), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + len, top), cornerPaint);
    // 우상단
    canvas.drawLine(Offset(left + boxW - len, top), Offset(left + boxW, top), cornerPaint);
    canvas.drawLine(Offset(left + boxW, top), Offset(left + boxW, top + len), cornerPaint);
    // 좌하단
    canvas.drawLine(Offset(left, top + boxH - len), Offset(left, top + boxH), cornerPaint);
    canvas.drawLine(Offset(left, top + boxH), Offset(left + len, top + boxH), cornerPaint);
    // 우하단
    canvas.drawLine(Offset(left + boxW, top + boxH - len), Offset(left + boxW, top + boxH), cornerPaint);
    canvas.drawLine(Offset(left + boxW, top + boxH), Offset(left + boxW - len, top + boxH), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
