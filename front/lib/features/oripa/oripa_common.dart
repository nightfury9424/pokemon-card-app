import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/app_list_ui.dart';
import 'data/oripa_prizes.dart';

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

/// 오리파 상품 mock 타일 — 이름+레어도를 렌더. **카드 도메인/CDN 무관.**
/// 이름↔이미지 일치가 구조적으로 보장(타일이 상품명을 그대로 렌더). 상품판·결과시트가
/// 동일 소스로 이 타일을 쓴다. 미래엔 사장님 업로드 이미지로 교체될 자리.
class OripaPrizeTile extends StatelessWidget {
  final OripaPrize prize;
  final double nameSize;
  const OripaPrizeTile({super.key, required this.prize, this.nameSize = 10});

  @override
  Widget build(BuildContext context) {
    final rc = AppColors.rarityColor(prize.rarity);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, color: rc, size: nameSize * 2.0),
          SizedBox(height: nameSize * 0.5),
          Flexible(
            child: Text(
              prize.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: nameSize,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
          SizedBox(height: nameSize * 0.3),
          AppRarityBadge(prize.rarity, fontSize: nameSize * 0.8),
        ],
      ),
    );
  }
}
