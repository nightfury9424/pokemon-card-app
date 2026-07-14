import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 오리파 봉인 포일팩 (리빌 Phase 1) — **자산 기반**.
///
/// 공통 마스터 실루엣 1개에서 파생한 4레이어를 합성:
///   `base`(닫힘) · `open_body`(개봉구 암부) · `top_strip`(뜯기는 상단 크림프) · `mouth_shadow`(입구 암부).
/// 재질만 다른 3종(네이비/홀로/실버)은 [assetDir]만 바꾸면 동일 구조로 동작.
///
/// - [tearProgress] 0→1: `top_strip`이 위로 찢겨 올라가며(±약간 회전·페이드) 개봉구 노출.
/// - 브랜딩(POKEFOLIO·오리파명)은 **하단 고정 오버레이**(상단 0–30%는 카드 상승 공간 → 비움).
/// - 번호는 팩에 안 그림(CTA 표시) — [number]는 API 호환용.
/// - 미세 3D(±약 1°)만. 카드뒷면·이동 반사광·아우라는 상위(Flutter) 레이어.
class OripaSealedPack extends StatelessWidget {
  // 마스터 자산 실측 비율(네이비 base 975×1503). 3종 동일 실루엣.
  static const double designWidth = 975, designHeight = 1503;
  static const double aspectRatio = designHeight / designWidth; // ≈1.541
  static const double widthFactor = 0.66; // 화면폭의 66%
  static const double minWidth = 196, maxWidth = 360;
  static const double _stripFrac = 0.14; // 상단 크림프=개봉구 높이 비율(레이어 파생과 일치)

  final String title;
  final int number; // API 호환(팩엔 안 그림)
  final double tearProgress; // 0=닫힘, 1=상단 완전 절취
  final double tilt; // deg
  final String assetDir;

  const OripaSealedPack({
    super.key,
    required this.title,
    required this.number,
    this.tearProgress = 0,
    this.tilt = 0,
    this.assetDir = 'assets/oripa/packs/navy',
  });

  static double widthFor(double availableWidth) =>
      (availableWidth * widthFactor).clamp(minWidth, maxWidth);

  Widget _img(String name, {BoxFit fit = BoxFit.fill}) => Image.asset(
        '$assetDir/$name',
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = widthFor(c.maxWidth);
        final h = w * aspectRatio;
        return SizedBox(width: w, height: h, child: _pack(w, h));
      },
    );
  }

  Widget _pack(double w, double h) {
    final t = tearProgress.clamp(0.0, 1.0);
    final stripH = h * _stripFrac;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0011) // 원근
        ..rotateX(-0.02), // 상단이 살짝 뒤로 — 미세 입체(≈1.1°)
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 몸체(개봉구 암부 포함)
          Positioned.fill(child: _img('open_body.png')),
          // 입구 암부 — 절취될수록 깊어짐
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: stripH,
            child: Opacity(opacity: t, child: _img('mouth_shadow.png')),
          ),
          // 상단 크림프 스트립 — tearProgress로 위로 찢겨 올라감(+회전·페이드)
          Positioned.fill(
            child: Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(t * w * 0.10, -t * stripH * 1.9),
                child: Transform.rotate(
                  angle: -t * 0.14 + tilt * math.pi / 180,
                  alignment: Alignment.topLeft,
                  child: _img('top_strip.png'),
                ),
              ),
            ),
          ),
          // ── 하단 고정 브랜딩 오버레이 (상단 0–30% 비움) ──
          Positioned(
            top: h * 0.62,
            left: 0,
            right: 0,
            child: Text(
              'POKEFOLIO',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFE9D9A8),
                fontSize: w * 0.052,
                fontWeight: FontWeight.w800,
                letterSpacing: w * 0.02,
              ),
            ),
          ),
          Positioned(
            top: h * 0.715,
            left: w * 0.13,
            right: w * 0.13,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: w * 0.056,
                fontWeight: FontWeight.w800,
                height: 1.12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
