import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';

class GradingCaptureScreen extends StatefulWidget {
  const GradingCaptureScreen({super.key});
  @override
  State<GradingCaptureScreen> createState() => _GradingCaptureScreenState();
}

class _GradingCaptureScreenState extends State<GradingCaptureScreen> {
  CameraController? _controller;
  bool _cameraReady = false;
  int _step = 0;
  final List<File> _photos = [];

  static const _stepLabels = [
    ('앞면 전체', '카드 앞면 전체가 화면에 꽉 차도록'),
    ('뒷면 전체', '카드 뒷면 전체가 화면에 꽉 차도록'),
    ('앞 좌상단', '앞면 왼쪽 위 모서리 클로즈업'),
    ('앞 우상단', '앞면 오른쪽 위 모서리 클로즈업'),
    ('앞 좌하단', '앞면 왼쪽 아래 모서리 클로즈업'),
    ('앞 우하단', '앞면 오른쪽 아래 모서리 클로즈업'),
    ('뒤 좌상단', '뒷면 왼쪽 위 모서리 클로즈업'),
    ('뒤 우상단', '뒷면 오른쪽 위 모서리 클로즈업'),
    ('뒤 좌하단', '뒷면 왼쪽 아래 모서리 클로즈업'),
    ('뒤 우하단', '뒷면 오른쪽 아래 모서리 클로즈업'),
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    if (mounted) setState(() => _cameraReady = true);
  }

  Future<void> _capture() async {
    if (_controller == null || !_cameraReady) return;
    final xfile = await _controller!.takePicture();
    _photos.add(File(xfile.path));
    if (_step < 9) {
      setState(() => _step++);
    } else {
      await _controller!.dispose();
      if (mounted) context.push('/grading/result', extra: {'photos': _photos});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (label, hint) = _stepLabels[_step];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_cameraReady && _controller != null)
          Positioned.fill(child: CameraPreview(_controller!)),
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_step + 1) / 10,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(AppColors.blue),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_step + 1}/10', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(hint, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ),
        ),
        Positioned(
          bottom: 48, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _capture,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  color: Colors.white24,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
