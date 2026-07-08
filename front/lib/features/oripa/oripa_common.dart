import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pressable.dart';

/// 준비 중 mock 안내 토스트 — 라우트 이동 시 잔존 방지.
/// 앱 레벨 ScaffoldMessenger의 floating SnackBar는 Navigator 위라 push해도 안 사라짐 →
/// 기존 것 즉시 해제 + 짧게 표시해서 다음 화면까지 안 따라오게 한다.
void oripaComingSoon(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ),
    );
}

/// 오리파 전용 상단바 — 뒤로가기(자동) + 타이틀. 독립 서비스 톤 유지.
AppBar oripaAppBar(String title) {
  return AppBar(
    backgroundColor: AppColors.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
  );
}

/// 오리파 주요 액션 버튼 (풀폭).
class OripaPrimaryButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const OripaPrimaryButton({
    super.key,
    required this.label,
    this.color = AppColors.blue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

/// 오리파 구수 진행 바 — 판매된 비율(soldFraction)만큼 채운다.
class OripaSlotBar extends StatelessWidget {
  final double soldFraction;
  const OripaSlotBar(this.soldFraction, {super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: soldFraction.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: AppColors.divider,
        valueColor: const AlwaysStoppedAnimation(AppColors.blue),
      ),
    );
  }
}
