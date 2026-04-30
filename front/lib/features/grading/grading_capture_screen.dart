import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';

class GradingCaptureScreen extends StatefulWidget {
  const GradingCaptureScreen({super.key});
  @override
  State<GradingCaptureScreen> createState() => _GradingCaptureScreenState();
}

class _GradingCaptureScreenState extends State<GradingCaptureScreen> {
  int _step = 0;
  final List<File> _photos = [];
  final _picker = ImagePicker();
  bool _isCapturing = false;

  static const _stepLabels = [
    ('앞면 전체', '카드 앞면 전체가 찍힌 사진 선택'),
    ('뒷면 전체', '카드 뒷면 전체가 찍힌 사진 선택'),
    ('앞 좌상단', '앞면 왼쪽 위 코너를 클로즈업한 사진 선택'),
    ('앞 우상단', '앞면 오른쪽 위 코너를 클로즈업한 사진 선택'),
    ('앞 좌하단', '앞면 왼쪽 아래 코너를 클로즈업한 사진 선택'),
    ('앞 우하단', '앞면 오른쪽 아래 코너를 클로즈업한 사진 선택'),
    ('뒤 좌상단', '뒷면 왼쪽 위 코너를 클로즈업한 사진 선택'),
    ('뒤 우상단', '뒷면 오른쪽 위 코너를 클로즈업한 사진 선택'),
    ('뒤 좌하단', '뒷면 왼쪽 아래 코너를 클로즈업한 사진 선택'),
    ('뒤 우하단', '뒷면 오른쪽 아래 코너를 클로즈업한 사진 선택'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureNext());
  }

  Future<void> _captureNext() async {
    if (_isCapturing) return;
    _isCapturing = true;

    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );

    _isCapturing = false;

    if (xfile == null) {
      if (mounted) context.pop();
      return;
    }

    _photos.add(File(xfile.path));

    if (_step < 9) {
      setState(() => _step++);
      _captureNext();
    } else {
      if (mounted) context.push('/grading/result', extra: {'photos': _photos});
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, hint) = _stepLabels[_step];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: (_step + 1) / 10,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(AppColors.blue),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${_step + 1}/10',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
              const SizedBox(height: 24),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(hint,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white38, size: 14),
                  SizedBox(width: 6),
                  Text('흰 단색 배경 · 플래시 OFF · 카드 70% 이상',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
              const Spacer(),
              Center(
                child: _isCapturing
                    ? const CircularProgressIndicator(color: AppColors.blue)
                    : ElevatedButton.icon(
                        onPressed: _captureNext,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('사진 선택'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                      ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
