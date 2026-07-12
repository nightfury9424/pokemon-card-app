import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// 오리파 봉인 카드팩 (리빌 Phase 1 · Step 1) — 닫힌 포일 팩 + 상단 절취 스트립.
///
/// - **반응형**: 사용 가능 너비의 [widthFactor](≈66%)를 폭으로, aspect([aspectRatio])로 높이 산출.
///   [minWidth]~[maxWidth]로만 제한(작은/큰 화면 모두 화면폭 62~70% 유지). 내부 치수는 폭에 비례.
/// - 팩 **몸체는 고정 중심(anchor)**. 등장 연출은 호출부에서 center-anchored scale+opacity만(translate 금지).
/// - 상단 스트립만 [tearProgress]로 가로 분리 → 개봉구 노출.
/// - 차등 아우라 / 카드 뒷면 상승 / 플립은 Step 2~ 이후 이 위에 얹는다(여기엔 없음).
/// - 임시 포켓볼형 아이콘 미사용(승인 조건) — 중립 기하 봉인 심벌([_SealMarkPainter]).
class OripaSealedPack extends StatelessWidget {
  // 디자인 기준(폭 220)과 반응형 규칙.
  static const double designWidth = 220, designHeight = 300;
  static const double aspectRatio = designHeight / designWidth; // ≈1.364
  static const double widthFactor = 0.66; // 화면폭의 66%
  static const double minWidth = 196, maxWidth = 330;

  // 포일/골드 — 스토리보드 v4 팔레트(리빌 전용 몰입면, 리스트 킷 예외).
  static const Color _foilTop = Color(0xFF4B49A0);
  static const Color _foilMid = Color(0xFF6A5AC0);
  static const Color _foilBot = Color(0xFF2E2C63);
  static const Color _gold = Color(0xFFD8B25A);
  static const Color _gold2 = Color(0xFFFFE4A0);

  final String title;
  final int number;
  final double tearProgress; // 0=닫힘, 1=스트립 완전 분리
  final double tilt; // deg

  const OripaSealedPack({
    super.key,
    required this.title,
    required this.number,
    this.tearProgress = 0,
    this.tilt = 0,
  });

  static double widthFor(double availableWidth) =>
      (availableWidth * widthFactor).clamp(minWidth, maxWidth);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = widthFor(c.maxWidth);
        final h = w * aspectRatio;
        final s = w / designWidth; // 내부 치수 스케일
        return SizedBox(width: w, height: h, child: _pack(s));
      },
    );
  }

  Widget _pack(double s) {
    final stripH = 46 * s;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: _body(s, stripH)),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: stripH,
          child: Opacity(
            opacity: (1 - tearProgress).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(tearProgress * (designWidth * s + 48 * s), 0),
              child: Transform.rotate(
                angle: tilt * math.pi / 180,
                alignment: Alignment.centerLeft,
                child: _strip(s, stripH),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(double s, double stripH) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18 * s),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_foilTop, _foilMid, _foilBot],
          stops: [0, 0.55, 1],
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28 * s,
              offset: Offset(0, 16 * s)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18 * s),
        child: Stack(
          children: [
            // 대각 포일 광택
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-1, -1),
                    end: const Alignment(1, 0.2),
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // 상단 개봉구(스트립 아래 어두운 recess — 절취되면 드러남)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: stripH,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0C0B1A), Color(0x000C0B1A)],
                  ),
                ),
              ),
            ),
            // 내용
            Padding(
              padding: EdgeInsets.fromLTRB(18 * s, stripH + 14 * s, 18 * s, 18 * s),
              child: Column(
                children: [
                  Text('POKEFOLIO',
                      style: TextStyle(
                          color: _gold2,
                          fontSize: 13 * s,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3 * s)),
                  const Spacer(),
                  // 중립 기하 봉인 심벌 (임시 포켓볼 아이콘 대체)
                  SizedBox(
                    width: 96 * s,
                    height: 96 * s,
                    child: CustomPaint(
                      painter: _SealMarkPainter(ring: _gold, fill: _gold2),
                    ),
                  ),
                  const Spacer(),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13 * s,
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 8 * s),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 14 * s, vertical: 5 * s),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: _gold.withValues(alpha: 0.5)),
                    ),
                    child: Text('No. $number',
                        style: TextStyle(
                            color: _gold2,
                            fontSize: 15 * s,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5 * s)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 상단 절취 스트립 — 몸체보다 밝은 포일 + 하단 절취선 + 우측 pull-tab(내측).
  Widget _strip(double s, double stripH) {
    return SizedBox(
      width: designWidth * s,
      height: stripH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(18 * s), bottom: Radius.circular(3 * s)),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7C6BD0), Color(0xFF524698)],
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 8 * s,
                      offset: Offset(0, 4 * s)),
                ],
              ),
            ),
          ),
          Center(
            child: Text('개봉',
                style: TextStyle(
                    color: _gold2,
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2 * s)),
          ),
          Positioned(
              left: 8 * s,
              right: 8 * s,
              bottom: 3 * s,
              child: const _Perforation()),
          // 우측 pull-tab (스트립 내측 — 클리핑 방지)
          Positioned(
            right: 8 * s,
            top: stripH / 2 - 10 * s,
            child: Container(
              width: 22 * s,
              height: 20 * s,
              padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 5 * s),
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(5 * s),
              ),
              // 순수 위젯 grip(폰트/아이콘 무관) — 세로 홈 2줄.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                    2,
                    (_) => Container(
                        width: 1.5 * s, color: const Color(0xFF3A2E12))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 절취선 점선 — 얇은 대시 반복.
class _Perforation extends StatelessWidget {
  const _Perforation();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        const dash = 5.0, gap = 4.0;
        final n = (c.maxWidth / (dash + gap)).floor().clamp(0, 200);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            n,
            (_) => Container(
              width: dash,
              height: 1.5,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
        );
      },
    );
  }
}

/// 중립 기하 봉인 심벌 — 동심 링 + 내접 육각형 + 방사 눈금 + 중심점.
/// 폰트/아이콘 의존 없음(골든에서 실제 모습 그대로 렌더). 브랜드 심벌 확정 시 교체 지점.
class _SealMarkPainter extends CustomPainter {
  final Color ring;
  final Color fill;
  const _SealMarkPainter({required this.ring, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final stroke = size.width * 0.022;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = ring;

    canvas.drawCircle(c, r * 0.96, ringPaint);
    canvas.drawCircle(c, r * 0.64, ringPaint..strokeWidth = stroke * 0.8);

    // 내접 육각형
    final hex = Path();
    for (int i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.64;
      i == 0 ? hex.moveTo(p.dx, p.dy) : hex.lineTo(p.dx, p.dy);
    }
    hex.close();
    canvas.drawPath(
        hex,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round
          ..color = ring);

    // 링 사이 방사 눈금
    final tick = Paint()
      ..color = ring
      ..strokeWidth = stroke * 0.9
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * r * 0.72, c + dir * r * 0.88, tick);
    }

    // 중심점
    canvas.drawCircle(c, r * 0.12, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(covariant _SealMarkPainter old) =>
      old.ring != ring || old.fill != fill;
}
