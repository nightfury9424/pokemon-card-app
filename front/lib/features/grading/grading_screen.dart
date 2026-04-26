import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class GradingScreen extends StatelessWidget {
  const GradingScreen({super.key});

  static const _steps = [
    ('앞면 전체', '센터링 측정'),
    ('뒷면 전체', '화이트닝 감지'),
    ('앞 좌상단', '코너 마모'),
    ('앞 우상단', '코너 마모'),
    ('앞 좌하단', '코너 마모'),
    ('앞 우하단', '코너 마모'),
    ('뒤 좌상단', '코너 + 화이트닝'),
    ('뒤 우상단', '코너 + 화이트닝'),
    ('뒤 좌하단', '코너 + 화이트닝'),
    ('뒤 우하단', '코너 + 화이트닝'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text('등급 예측', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A3A6A), Color(0xFF0D2040)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.grade_rounded, color: AppColors.blue, size: 36),
                const SizedBox(height: 12),
                const Text('카드 등급 예측',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('사진 10장으로 센터링, 코너, 표면, 화이트닝을\n분석해 예상 등급을 알려드립니다.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('촬영 순서', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._steps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: AppColors.blue.withOpacity(0.15), shape: BoxShape.circle),
                child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 10),
              Text(e.value.$1, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              const SizedBox(width: 6),
              Text('(${e.value.$2})', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ]),
          )),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.push('/grading/capture'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blue,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('시작하기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
