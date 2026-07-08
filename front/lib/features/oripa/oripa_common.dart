import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/pressable.dart';
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

/// 오리파 상품 mock 타일 — 상품의 image(오리파 전용 asset)를 표시. **카드 도메인/CDN 무관.**
/// 상품판·결과시트가 동일 image source로 이 타일을 쓴다(같은 prize=같은 이미지=일관성 보장).
/// 미래엔 prize.image가 사장님 업로드 S3 URL로 바뀌면 여기서 Image.network로 교체.
class OripaPrizeTile extends StatelessWidget {
  final OripaPrize prize;
  const OripaPrizeTile({super.key, required this.prize});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            prize.image,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: AppColors.surfaceElevated,
              alignment: Alignment.center,
              child: const Icon(Icons.inventory_2_rounded,
                  color: AppColors.textMuted, size: 24),
            ),
          ),
          // 이미지 스크림(디자인킷 예외) + 상품명 — placeholder여도 무슨 상품인지 읽힘.
          // 상품판·결과가 동일 prize.image + 동일 prize.name 표시 → 번호 오리파 연결 판정 가능.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xD9000000)],
                ),
              ),
              child: Text(
                prize.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
