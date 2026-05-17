import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds — 더 딥 다크
  static const bg            = Color(0xFF04080F);
  static const surface       = Color(0xFF090E18);
  static const surfaceCard   = Color(0xFF0D1520);
  static const surfaceElevated = Color(0xFF111D2C);

  // Accents
  static const blue      = Color(0xFF1B64DA);
  static const blueLight = Color(0xFF4D8FEA);
  static const blueDeep  = Color(0xFF0B3D8C); // selected chip 배경 (blue 너무 밝아서)
  static const gold      = Color(0xFFFFCC00);
  static const green     = Color(0xFF05C072);
  static const red       = Color(0xFFEF4444);

  // Text
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF7A93B0);
  static const textMuted     = Color(0xFF3A5470);

  // Divider — 보정: 더 어두운 #111E2E에서 1.5단계 lighter로 가시성 ↑
  static const divider     = Color(0xFF1A2638);
  static const dividerSoft = Color(0xFF0F1A28); // 미세한 구분용

  // Rarity colors
  static const raritySSR = Color(0xFFFF6B6B);
  static const raritySAR = Color(0xFFFFD700);
  static const rarityCSR = Color(0xFF00E5FF);
  static const rarityCHR = Color(0xFF4FC3F7);
  static const rarityUR  = Color(0xFFCE93D8);
  static const raritySR  = Color(0xFF9575CD);
  static const rarityAR  = Color(0xFFFF9800);
  static const rarityBWR = Color(0xFFB2FFB2);

  static Color rarityColor(String rarity) {
    switch (rarity) {
      case 'SSR': return raritySSR;
      case 'SAR': return raritySAR;
      case 'BWR': return rarityBWR;
      case 'CSR': return rarityCSR;
      case 'CHR': return rarityCHR;
      case 'UR':  return rarityUR;
      case 'SR':  return raritySR;
      case 'AR':  return rarityAR;
      default:    return textMuted;
    }
  }

  // 레어도별 글로우 색상 (카드 테두리/그림자용)
  static Color rarityGlow(String rarity) {
    switch (rarity) {
      case 'SSR': return const Color(0xFFFF6B6B);
      case 'SAR': return const Color(0xFFFFD700);
      case 'BWR': return const Color(0xFF90EE90);
      case 'CSR': return const Color(0xFF00E5FF);
      case 'CHR': return const Color(0xFF4FC3F7);
      case 'UR':  return const Color(0xFFCE93D8);
      case 'SR':  return const Color(0xFF9575CD);
      case 'AR':  return const Color(0xFFFF9800);
      default:    return Colors.transparent;
    }
  }

  static String formatPrice(int price) {
    if (price <= 0) return '0원';
    final rounded = (price / 10).round() * 10;
    final s = rounded.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$s원';
  }
}

/// 8px 기준 spacing scale. 모든 화면의 padding/margin/gap에 사용.
/// REFACTOR_2026-05-12.md 4차 디자인 시스템.
class AppSpacing {
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 20;
  static const double xxl  = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

/// Corner radius scale.
class AppRadius {
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 20;
  static const double xxl  = 24;
  static const double pill = 999; // 캡슐 모양 (chip, button)
}

/// 다층 그림자 — Toss/Linear 스타일.
/// 단일 BoxShadow는 단조로움. ambient + key 조합으로 깊이 표현.
class AppShadows {
  /// 작은 카드, chip, 작은 elevation
  static List<BoxShadow> light(Color baseColor) => [
        BoxShadow(
          color: baseColor.withValues(alpha: 0.18),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: baseColor.withValues(alpha: 0.08),
          blurRadius: 1,
          offset: const Offset(0, 1),
        ),
      ];

  /// 중간 elevation — sheet, dropdown, FAB 등
  static List<BoxShadow> medium(Color baseColor) => [
        BoxShadow(
          color: baseColor.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: baseColor.withValues(alpha: 0.12),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  /// 큰 elevation — 모달, 떠 있는 큰 카드
  static List<BoxShadow> heavy(Color baseColor) => [
        BoxShadow(
          color: baseColor.withValues(alpha: 0.42),
          blurRadius: 32,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: baseColor.withValues(alpha: 0.18),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  /// FAB 액션색 글로우 (centerDocked FAB 같은 강조 요소)
  static List<BoxShadow> glow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: 20,
          spreadRadius: 1,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.18),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
}

/// Typography scale — Toss/Robinhood 스타일 kinetic numbers + 명확한 위계.
/// 4차-Round2: AI 틱 제거 (단조 textStyle 반복 → 의도적 위계).
class AppText {
  /// 32sp, 포트폴리오 총액 같은 hero 숫자 (kinetic)
  static const TextStyle display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.2,
    height: 1.05,
    color: AppColors.textPrimary,
  );

  /// 22sp, 페이지 제목/큰 섹션 헤더
  static const TextStyle h1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.15,
    color: AppColors.textPrimary,
  );

  /// 18sp, 섹션 제목
  static const TextStyle h2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  /// 16sp, 카드 제목 / 리스트 아이템 강조
  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  /// 14sp, 본문 강조
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  /// 13sp, 본문 기본
  static const TextStyle body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  /// 12sp, 캡션 / 보조 설명
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.textSecondary,
  );

  /// 11sp, 라벨 (chip, badge)
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: AppColors.textSecondary,
  );

  /// 11sp, 더 약한 보조 (분류/메타)
  static const TextStyle muted = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );
}
