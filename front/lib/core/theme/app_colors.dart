import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds — 더 딥 다크
  static const bg            = Color(0xFF04080F);
  static const surface       = Color(0xFF090E18);
  static const surfaceCard   = Color(0xFF0D1520);
  static const surfaceElevated = Color(0xFF111D2C);

  // Accents
  static const blue      = Color(0xFF3D7DCA);
  static const blueLight = Color(0xFF5B9BD5);
  static const gold      = Color(0xFFFFCC00);
  static const green     = Color(0xFF10B981);
  static const red       = Color(0xFFEF4444);

  // Text
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF7A93B0);
  static const textMuted     = Color(0xFF3A5470);

  // Divider
  static const divider = Color(0xFF111E2E);

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
