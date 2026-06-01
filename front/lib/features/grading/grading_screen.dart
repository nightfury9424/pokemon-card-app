import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class _GuideRow extends StatelessWidget {
  final bool ok;
  final String text;
  const _GuideRow({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: ok ? AppColors.green : AppColors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: ok ? AppColors.textPrimary : AppColors.textSecondary,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class GradingScreen extends StatelessWidget {
  const GradingScreen({super.key});

  static const _steps = [
    ('앞면 전체', '센터링 · 코너 · 표면 측정'),
    ('뒷면 전체', '화이트닝 · 코너 감지'),
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
                const Text('앞면·뒷면 사진 2장만 선택하면\n센터링, 코너, 표면, 화이트닝을 분석해 예상 등급을 알려드립니다.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('사진 선택 순서', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
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
          const SizedBox(height: 24),
          const Text('사진 촬영 팁 (미리 찍어두세요)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1400),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gold.withOpacity(0.35)),
            ),
            child: const Column(
              children: [
                _GuideRow(ok: true,  text: '흰 종이 등 밝은 단색 배경 사용'),
                _GuideRow(ok: true,  text: '자연광 또는 균일한 실내등 — 플래시 OFF'),
                _GuideRow(ok: true,  text: '카드가 화면의 70% 이상 차지하도록'),
                _GuideRow(ok: true,  text: '코너 클로즈업 시 코너를 화면 중앙에'),
                Divider(color: Color(0xFF2A2400), height: 16),
                _GuideRow(ok: false, text: '검정·어두운 배경 (마우스패드 등)'),
                _GuideRow(ok: false, text: '그림자 또는 먼지가 있는 배경'),
                _GuideRow(ok: false, text: '카드가 비스듬히 기울어진 상태'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.blue.withOpacity(0.25)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: AppColors.blue, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '그레이딩은 내 자산에 등록된 카드에 대해 진행돼요.\n아래에서 자산을 선택하거나 새 카드를 등록해 주세요.',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => context.push('/grading/select-asset'),
            icon: const Icon(Icons.style_rounded, color: Colors.white),
            label: const Text('내 자산에서 선택', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blue,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.push('/scanner'),
            icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.textPrimary),
            label: const Text('카드 스캐너로 새 카드 등록', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.divider),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}
