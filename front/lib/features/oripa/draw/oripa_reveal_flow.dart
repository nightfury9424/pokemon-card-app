import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../data/reveal_models.dart';
import 'reveal_view.dart' show RevealEntryMode;

/// 오리파 리빌 플로우 — **승인 HTML v3 이식**
/// (진실원: `tool/oripa_pack/preview/reveal_motion_v3_approved.html`, 2026-07-15 승인)
///
/// 가상 스테이지 400×760을 [FittedBox]로 스케일 — HTML과 px 계약 동일.
///   개봉: 부유 → 드래그 절취(글로우 트레일·스파크) → 조각 이탈 140ms(얇게·rotateX)
///       → 카드 선노출(절취 70%부터) → 랩퍼 탈거 520ms(rotateX·scaleX 수축, 말미 13%만 fade)
///       → 정착 반동(위7px/아래2px) + 완만 확대(215→232)
///   NORMAL: 탭 → 담백 플립 360ms → 앞면.
///   HIT: 아우라 점화 330ms(연기 파티클+후광+림) → 탭 → 전진 80ms → 88° 확회전 170ms
///       → 옆면 선광과 함께 암전 흡수 → 검은 무대 정중앙 문구(블러+페이드, 하나씩)
///       → 정적 → 흰 코어→금 링→백금 플래시(비네트) → HERO(화면 62%) → 감상.
///
/// 계약(불변): [onRevealStarted]=탭/CTA 즉시(플립·연출 시작), [onHeroShown]=앞면/HERO
/// 완전 노출 후, [onResultReady]=감상 hold 후. 카드 탭과 CTA 버튼은 같은 exactly-once
/// 핸들러(오너락). 경로 분기는 descriptor.path만 참조. reduceMotion=모션 축소·pacing 유지.
class OripaRevealFlow extends StatefulWidget {
  final String title;
  final int number;
  final RevealDescriptor descriptor;
  final Widget heroFront; // 카드 앞면(상품 콘텐츠)
  final RevealEntryMode entryMode;
  final bool reduceMotion;
  final VoidCallback onRevealStarted;
  final VoidCallback onHeroShown;
  final VoidCallback onResultReady;
  const OripaRevealFlow({
    super.key,
    required this.title,
    required this.number,
    required this.descriptor,
    required this.heroFront,
    required this.onRevealStarted,
    required this.onHeroShown,
    required this.onResultReady,
    this.entryMode = RevealEntryMode.fresh,
    this.reduceMotion = false,
  });

  @override
  State<OripaRevealFlow> createState() => _OripaRevealFlowState();
}

// ── 가상 스테이지 지오메트리 (HTML과 동일 — 크기 계약 277>233>215<232) ──
class _G {
  static const stW = 400.0, stH = 760.0;
  // 자산 실루엣 실측: open_body 캔버스 975×1503, 실루엣 폭 73.2%·높이 92.5%·top 0.6%·중심 +0.41%
  static const packVisW = 277.0;
  static const packW = packVisW / .732; // 378.4 (캔버스 렌더 폭)
  static const packH = packW * 1503 / 975; // 583.4
  static const packX = stW / 2 - packW * .5041; // 9.2
  static const packVisH = packH * .925; // 539.6
  static const packVisTop = (stH - packVisH) / 2; // 110.2
  static const packY = packVisTop - packH * .006; // 106.7
  static const mouthH = packH * .14; // 81.7
  static const mouthY = packY + mouthH; // 188.4 — 가림 기준선
  static const mouthW = 233.0;
  static const cardW = 215.0, cardH = cardW * 88 / 63; // 300.3
  static const cardX = (stW - cardW) / 2;
  static const cardTop0 = mouthY + 4;
  static const cardCy = 283.0; // 정착 후 카드 중심
  static const heroScale = (stH * .62) / cardH; // HERO = 화면 높이 62%
  static const heroCy = 380.0;
  static const settleScale = 232.0 / 215.0; // 정착 확대(완만, 팝 금지)
}

// ── 승인 타이밍(ms) — 실기기 튜닝은 Phase 2 ──
class _T {
  static const cutAuto = 220; // 드래그 82% 이후 자동 완결
  static const cap = 140; // 조각 이탈
  static const preSlide = 120; // 카드 선노출 2차(+30px)
  static const slideA = 190, slideB = 210; // 랩퍼 인출→급강하
  static const bump = 220; // 정착 반동(위7/아래2)
  static const auraIgnite = 330;
  static const flip = 360; // NORMAL
  static const pop = 80, spin = 230; // 88° 회전+암전+옆면 선광(연동 창)
  static const beatIn = 220, beatOut = 180, beatGap = 80;
  static const holdFirst = 360, holdMid = 200, holdLast = 520;
  static const quiet = 260;
  static const climax = 740; // 코어320·링360·플래시80/150·HERO 등장 380 겹침 창
  static const heroHold = 700; // 감상
}

enum _Ph { settle, cutting, cap, preSlide, slide, bump, wait, flip, frontHold,
  pop, spin, beats, quiet, climax, heroHold, done }

class _OripaRevealFlowState extends State<OripaRevealFlow>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  _Ph _ph = _Ph.settle;
  double _phMs = 0; // 현재 페이즈 경과
  double _tMs = 0; // 전체 경과(부유·펄스·입자용)
  double _cutP = 0, _cutFrom = 0; // 절취 진행(드래그 구동)
  bool _hz60 = false, _hz82 = false;
  bool _started = false, _heroShown = false, _resultFired = false;
  static const double _tearDist = 220; // 드래그 참조 거리(px) — Step1 계약 유지

  bool get _hit => widget.descriptor.path == RevealPath.hit;
  late final bool _recovered = widget.entryMode != RevealEntryMode.fresh;
  int get _beatCount => widget.descriptor.clues.length;
  double _d(num ms) => widget.reduceMotion ? 0 : ms.toDouble();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    switch (widget.entryMode) {
      case RevealEntryMode.fresh:
        _ph = _Ph.settle;
      case RevealEntryMode.committedRecovery:
        _ph = _Ph.climax; // HERO 직행(리플레이 금지) — climax 말미로 점프
        _phMs = _d(_T.climax);
      case RevealEntryMode.revealedRecovery:
        _ph = _Ph.heroHold;
        _phMs = 0;
        _heroShown = true; // onHeroShown 재호출 금지
        WidgetsBinding.instance.addPostFrameCallback((_) => _fireResult());
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration el) {
    final ms = el.inMicroseconds / 1000.0;
    final dt = ms - _tMs;
    _tMs = ms;
    _phMs += dt;
    _advance();
    if (mounted) setState(() {});
  }

  void _go(_Ph p) {
    _ph = p;
    _phMs = 0;
  }

  // 페이즈 자동 전이 (모션 구간만 — wait/hold는 콜백·탭이 전이)
  void _advance() {
    switch (_ph) {
      case _Ph.settle:
      case _Ph.wait:
      case _Ph.done:
        break;
      case _Ph.cutting:
        _cutP = (_cutFrom + (1 - _cutFrom) *
                _ease(_phMs / math.max(1, _d(_T.cutAuto)))).clamp(0.0, 1.0);
        if (_cutP >= 1) {
          HapticFeedback.lightImpact();
          _go(_Ph.cap);
        }
      case _Ph.cap:
        if (_phMs >= _d(_T.cap)) _go(_Ph.preSlide);
      case _Ph.preSlide:
        if (_phMs >= _d(_T.preSlide)) _go(_Ph.slide);
      case _Ph.slide:
        if (_phMs >= _d(_T.slideA + _T.slideB)) _go(_Ph.bump);
      case _Ph.bump:
        if (_phMs >= _d(_T.bump)) _go(_Ph.wait);
      case _Ph.flip:
        if (_phMs >= _d(_T.flip)) {
          _fireHero();
          _go(_Ph.frontHold);
        }
      case _Ph.frontHold:
        if (_phMs >= _T.heroHold) { // hold = pacing, reduceMotion에도 유지
          _fireResult();
          _go(_Ph.done);
        }
      case _Ph.pop:
        if (_phMs >= _d(_T.pop)) _go(_Ph.spin);
      case _Ph.spin:
        if (_phMs >= _d(_T.spin)) _go(_Ph.beats);
      case _Ph.beats:
        if (_phMs >= _beatsTotal()) _go(_Ph.quiet);
      case _Ph.quiet:
        if (_phMs >= _d(_T.quiet)) _go(_Ph.climax);
      case _Ph.climax:
        if (_phMs >= _d(_T.climax)) {
          if (!_recovered) HapticFeedback.heavyImpact();
          _fireHero();
          _go(_Ph.heroHold);
        }
      case _Ph.heroHold:
        if (_phMs >= _T.heroHold) {
          _fireResult();
          _go(_Ph.done);
        }
    }
    if (_ph == _Ph.done && _ticker.isActive) _ticker.stop();
  }

  double _beatsTotal() {
    double t = 0;
    for (var i = 0; i < _beatCount; i++) {
      t += _d(_T.beatIn + _holdFor(i) + _T.beatOut + _T.beatGap);
    }
    return math.max(t, 1);
  }

  int _holdFor(int i) => i == 0
      ? _T.holdFirst
      : (i == _beatCount - 1 ? _T.holdLast : _T.holdMid);

  // ── 입력 ──
  void _onTearDrag(DragUpdateDetails d) {
    if (_ph != _Ph.settle && _ph != _Ph.cutting) return;
    if (_ph == _Ph.settle) {
      _ph = _Ph.cutting;
      _phMs = 0;
    }
    final next = (_cutP + d.delta.dx / _tearDist).clamp(0.0, 1.0);
    if (next > _cutP) _cutP = next;
    if (!_hz60 && _cutP >= .60) { _hz60 = true; HapticFeedback.lightImpact(); }
    if (!_hz82 && _cutP >= .82 && _cutFrom == 0) {
      _hz82 = true;
      HapticFeedback.mediumImpact();
      _cutFrom = _cutP;
      _phMs = 0; // 자동 완결 구간 시작
    }
  }

  /// 카드 탭 + CTA 버튼 = 동일 exactly-once 진입(오너락 계약).
  void _beginRevealOnce() {
    if (_ph != _Ph.wait || _started) return;
    _started = true;
    widget.onRevealStarted(); // ★애니 前 즉시 기록
    HapticFeedback.mediumImpact();
    _go(_hit ? _Ph.pop : _Ph.flip);
  }

  void _fireHero() {
    if (_heroShown) return;
    _heroShown = true;
    widget.onHeroShown(); // 앞면/HERO 완전 노출 후 → markRevealed
  }

  void _fireResult() {
    if (_resultFired) return;
    _resultFired = true;
    widget.onResultReady();
  }

  // ── 이징 ──
  static double _c01(double v) => v.clamp(0.0, 1.0);
  static double _p(double t, double a, double b) => _c01((t - a) / (b - a));
  static double _ease(double p) { // easeInOutCubic
    p = _c01(p);
    return p < .5 ? 4 * p * p * p : 1 - math.pow(-2 * p + 2, 3) / 2;
  }
  static double _eo(double p) { p = _c01(p); return 1 - math.pow(1 - p, 3).toDouble(); }
  static double _ei(double p) { p = _c01(p); return p * p * p; }

  // ═══════════ 프레임 파라미터 (승인 타임라인의 순수 함수) ═══════════
  _Frame _frame() {
    final f = _Frame();
    f.t = _tMs;
    f.pulse = .5 + .5 * math.sin(_tMs * 2 * math.pi / 1800);
    final opened = _ph.index >= _Ph.cap.index;
    f.bob = (_ph == _Ph.settle || _ph == _Ph.cutting)
        ? math.sin(_tMs / 380) * 2.2 : 0;
    f.cutP = opened ? 1 : _cutP;
    f.capP = _ph == _Ph.cap
        ? _eo(_phMs / math.max(1, _d(_T.cap)))
        : (_ph.index > _Ph.cap.index ? 1 : 0);
    // 랩퍼 하강: 인출 120px(pow.8) → 급강하 640px(cubic). fade는 py 660+만(마지막 13%).
    double py = f.bob;
    if (_ph == _Ph.slide) {
      final a = math.pow(_p(_phMs, 0, _d(_T.slideA)), .8).toDouble();
      final b = _ei(_p(_phMs, _d(_T.slideA), _d(_T.slideA + _T.slideB)));
      py += 120 * a + 640 * b;
    } else if (_ph.index > _Ph.slide.index) {
      py += 760;
    }
    f.py = py;
    f.slideP = _c01(py / 760);
    f.packOp = 1 - _c01((py - 660) / 100);
    // 카드 선노출(절취 70%부터 24px) → 이탈 후 +30px → 반동 → 확대
    final peek1 = 24 * _eo(_p(f.cutP, .7, 1));
    final peek2 = 30 * _eo(_ph == _Ph.preSlide
        ? _phMs / math.max(1, _d(_T.preSlide))
        : (_ph.index > _Ph.preSlide.index ? 1 : 0));
    double lift = 0;
    if (_ph == _Ph.bump) {
      lift = 7 * _eo(_p(_phMs, 0, _d(100))) - 2 * _ease(_p(_phMs, _d(100), _d(220)));
    } else if (_ph.index > _Ph.bump.index) {
      lift = 5;
    }
    f.cardScale = 1 + (_G.settleScale - 1) *
        (_ph == _Ph.bump ? _eo(_phMs / math.max(1, _d(_T.bump)))
            : (_ph.index > _Ph.bump.index ? 1 : 0));
    f.cardTop = _G.cardTop0 - peek1 - peek2 - lift;
    // 아우라 점화(정착 후 330ms 피어오름) — HIT만
    if (_hit && _ph.index >= _Ph.wait.index && _ph.index <= _Ph.spin.index) {
      f.auraP = _ph == _Ph.wait
          ? _ease(_phMs / math.max(1, _d(_T.auraIgnite)))
          : 1;
    }
    // NORMAL 플립
    if (_ph == _Ph.flip) f.flipP = _ease(_phMs / math.max(1, _d(_T.flip)));
    if (_ph == _Ph.frontHold || (_ph == _Ph.done && !_hit)) f.flipP = 1;
    // HIT 전환: 전진 → 88° 확회전 → 암전 → 옆면 선광
    if (_ph == _Ph.pop) f.popP = _eo(_phMs / math.max(1, _d(_T.pop)));
    if (_ph.index >= _Ph.spin.index && _hit) f.popP = 1;
    if (_ph == _Ph.spin) {
      f.spinDeg = 88 * _ease(_p(_phMs, 0, _d(170)));
      f.blackP = _ease(_p(_phMs, _d(100), _d(200)));
      f.edgeF = math.sin(math.pi * _p(_phMs, _d(130), _d(230)));
    } else if (_hit && _ph.index > _Ph.spin.index) {
      f.blackP = 1;
    }
    f.cardOn = !_hit || _ph.index <= _Ph.spin.index;
    // 문구 비트 (정중앙, blur+fade, 하나씩)
    if (_ph == _Ph.beats) {
      double st = 0;
      for (var i = 0; i < _beatCount; i++) {
        final hold = _holdFor(i).toDouble();
        final dur = _d(_T.beatIn) + _d(hold) + _d(_T.beatOut) + _d(_T.beatGap);
        if (_phMs >= st && _phMs < st + math.max(dur, 1)) {
          final lt = _phMs - st;
          double a = 0, bl = 0, sc = 1, ty = 0;
          if (widget.reduceMotion) {
            a = lt < _d(_T.beatIn) + hold ? 1 : 0; // 모션 축소·pacing 유지
          } else if (lt < _T.beatIn) {
            final p1 = _ease(lt / _T.beatIn);
            a = p1; bl = 7 * (1 - p1); sc = .97 + .03 * p1; ty = 5 * (1 - p1);
          } else if (lt < _T.beatIn + hold) {
            a = 1;
          } else if (lt < _T.beatIn + hold + _T.beatOut) {
            final po = _ease((lt - _T.beatIn - hold) / _T.beatOut);
            a = 1 - po; bl = 6 * po; sc = 1 + .02 * po;
          }
          f.beatIdx = i; f.beatA = a; f.beatBlur = bl; f.beatScale = sc; f.beatTy = ty;
          break;
        }
        st += math.max(dur, 1);
      }
    }
    // 클라이맥스: 흰 코어 → 금 링 → 백금 플래시(비네트) → HERO 등장
    if (_ph == _Ph.climax) {
      f.coreP = _ease(_p(_phMs, 0, _d(320)));
      f.ringP = _eo(_p(_phMs, _d(160), _d(520)));
      f.flashP = _phMs < _d(400)
          ? _ease(_p(_phMs, _d(320), _d(400)))
          : 1 - _eo(_p(_phMs, _d(400), _d(550)));
      f.heroP = _ease(_p(_phMs, _d(360), _d(740)));
    } else if (_hit && _ph.index > _Ph.climax.index) {
      f.heroP = 1;
    }
    // 재진입 복구: 경로 무관 검은 무대 HERO (리플레이 금지 계약)
    if (_recovered) {
      f.blackP = 1;
      f.cardOn = false;
      f.heroP = 1;
      f.coreP = 0; f.ringP = 0; f.flashP = 0;
      f.packOp = 0;
    }
    f.tapWait = _ph == _Ph.wait;
    return f;
  }

  // ═══════════ 빌드 ═══════════
  @override
  Widget build(BuildContext context) {
    final f = _frame();
    return LayoutBuilder(builder: (context, c) {
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _G.stW,
          height: _G.stH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onTearDrag,
            onTap: _beginRevealOnce,
            child: Stack(clipBehavior: Clip.none, children: [
              // L0: 배경 발광/입자 (additive) — 카드 뒤
              Positioned.fill(
                child: CustomPaint(
                  painter: _BackFxPainter(f, _hit),
                ),
              ),
              // L1: 입구 뒷벽 띠(카드 뒤) — open_body 11.3~14% 슬라이스 + 슬롯 암부
              if (f.packOp > 0 && f.cutP > 0)
                _wrapper(f, _PackBack(cutP: f.cutP)),
              // L2: 카드 (뒷면/플립/스핀)
              if (f.cardOn && !(_hit && f.blackP >= 1)) _card(f, hero: false),
              // L3: 랩퍼 앞면(카드 앞) + 브랜딩
              if (f.packOp > 0)
                _wrapper(f, _PackFront(title: widget.title)),
              // L4: 상단 조각(크림프) + 컷 글로우
              if (f.packOp > 0 && f.capP < 1) _packTop(f),
              // L5: 암전
              if (f.blackP > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: f.blackP,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                ),
              // L6: 옆면 선광 + 문구 + 코어/링/플래시 (암전 위)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _FrontFxPainter(f)),
                ),
              ),
              if (f.beatIdx >= 0) _beatText(f),
              // L7: HERO (암전 위, 화면 62%)
              if ((_hit || _recovered) && f.heroP > 0) _card(f, hero: true),
              // 탭 힌트 링 + CTA (오너락: 카드 탭과 동일 핸들러)
              if (f.tapWait) ..._waitUi(f),
              if (_ph == _Ph.settle || _ph == _Ph.cutting)
                Positioned(
                  left: 0, right: 0, bottom: 26,
                  child: Text('상단 탭을 옆으로 당겨 개봉하세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .35),
                          fontSize: 13)),
                ),
            ]),
          ),
        ),
      );
    });
  }

  /// 랩퍼 공통 변형 — 하강 + rotateX(어깨 수축) + scaleX + 말미 기울임(빈 봉지).
  Widget _wrapper(_Frame f, Widget child) {
    return Positioned(
      left: _G.packX, top: _G.packY,
      width: _G.packW, height: _G.packH,
      child: Opacity(
        opacity: f.packOp,
        child: Transform(
          alignment: Alignment.topCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 1 / 800)
            ..translateByDouble(0.0, f.py, 0, 1)
            ..rotateX(3.5 * f.slideP * math.pi / 180)
            ..scaleByDouble(1 - .015 * f.slideP, 1.0, 1, 1)
            ..rotateZ(1.1 * f.slideP * f.slideP * math.pi / 180),
          child: child,
        ),
      ),
    );
  }

  Widget _packTop(_Frame f) {
    return Positioned(
      left: _G.packX, top: _G.packY,
      width: _G.packW, height: _G.packH,
      child: Opacity(
        opacity: math.min(f.packOp, 1 - _c01((f.capP - .75) / .25)),
        child: Transform(
          alignment: Alignment.topCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 1 / 600)
            ..translateByDouble(26.0 * f.capP, f.bob - 14 * f.capP, 0, 1)
            ..rotateZ(4.5 * f.capP * math.pi / 180)
            ..rotateX(16 * f.capP * math.pi / 180),
          child: _AssetSlice(
            asset: 'assets/oripa/packs/navy/top_strip.png',
            fromFrac: 0, toFrac: .125, // 21% 얇게(하단 클립)
          ),
        ),
      ),
    );
  }

  Widget _card(_Frame f, {required bool hero}) {
    double top, scale, rotY;
    double op = 1;
    if (hero) {
      op = f.heroP;
      scale = _G.heroScale * (.95 + .05 * f.heroP);
      rotY = math.pi; // 앞면
      top = _G.heroCy - _G.cardH / 2 + 8 * (1 - f.heroP);
    } else {
      top = f.cardTop;
      scale = f.cardScale * (1 + .04 * f.popP);
      rotY = _hit
          ? f.spinDeg * math.pi / 180
          : f.flipP * math.pi;
    }
    final showFront = rotY > math.pi / 2;
    final rim = (f.auraP > .3 && f.cardOn) || f.heroP > .4;
    return Positioned(
      left: _G.cardX, top: top,
      width: _G.cardW, height: _G.cardH,
      child: IgnorePointer(
        child: Opacity(
          opacity: op,
          child: Transform.scale(
            scale: scale,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 1 / 1100)
                ..rotateY(rotY),
              child: showFront
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _front(rim))
                  : _CardBack(rim: rim, glow: f.auraP, sheenP: f.slideP),
            ),
          ),
        ),
      ),
    );
  }

  Widget _front(bool rim) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF101826),
        boxShadow: rim ? _CardBack.rimShadow : _CardBack.baseShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: FittedBox(fit: BoxFit.contain, child: widget.heroFront),
    );
  }

  Widget _beatText(_Frame f) {
    final clue = widget.descriptor.clues[f.beatIdx];
    final isName = f.beatIdx == _beatCount - 1;
    Widget text = Text(
      clue.text,
      key: const Key('reveal_clue'),
      textAlign: TextAlign.center,
      maxLines: 2,
      style: TextStyle(
        color: Colors.white,
        fontSize: isName ? 40 : (f.beatIdx == 0 ? 29 : 34),
        fontWeight: FontWeight.w900,
        height: 1.15,
      ),
    );
    if (f.beatBlur > 0.2) {
      text = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: f.beatBlur, sigmaY: f.beatBlur),
        child: text,
      );
    }
    return Positioned(
      left: 36, right: 36, top: 0, bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: _c01(f.beatA),
            child: Transform.translate(
              offset: Offset(0, f.beatTy),
              child: Transform.scale(scale: f.beatScale, child: text),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _waitUi(_Frame f) {
    final rw = _G.cardW * 1.08 + 16, rh = _G.cardH * 1.08 + 16;
    final ringT = (_tMs % 1500) / 1500;
    return [
      Positioned(
        left: _G.stW / 2 - rw / 2, top: _G.cardCy - rh / 2,
        width: rw, height: rh,
        child: IgnorePointer(
          child: Opacity(
            opacity: (.45 * (1 - _eo(ringT))).clamp(0.0, .45),
            child: Transform.scale(
              scale: 1 + .06 * _eo(ringT),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: .4), width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 0, right: 0, bottom: 68,
        child: Text(
          '${widget.number}번 상품 · 카드를 탭하세요',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white.withValues(alpha: .4), fontSize: 12.5),
        ),
      ),
      // CTA 버튼 — 카드 탭과 동일 핸들러(오너락 계약 유지)
      Positioned(
        left: 40, right: 40, bottom: 18,
        child: GestureDetector(
          onTap: _beginRevealOnce,
          child: Container(
            key: const Key('reveal_cta'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${widget.number}번 상품 확인하기',
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    ];
  }
}

// ── 프레임 파라미터 묶음 ──
class _Frame {
  double t = 0, pulse = 0, bob = 0;
  double cutP = 0, capP = 0, py = 0, slideP = 0, packOp = 1;
  double cardTop = _G.cardTop0, cardScale = 1;
  double auraP = 0, flipP = 0, popP = 0, spinDeg = 0, blackP = 0, edgeF = 0;
  bool cardOn = true, tapWait = false;
  int beatIdx = -1;
  double beatA = 0, beatBlur = 0, beatScale = 1, beatTy = 0;
  double coreP = 0, ringP = 0, flashP = 0, heroP = 0;
}

// ── 자산 세로 슬라이스 (fromFrac~toFrac 구간만 노출) ──
class _AssetSlice extends StatelessWidget {
  final String asset;
  final double fromFrac, toFrac;
  final double? brightness;
  const _AssetSlice({required this.asset, required this.fromFrac,
      required this.toFrac, this.brightness});

  @override
  Widget build(BuildContext context) {
    Widget img = Image.asset(asset,
        width: _G.packW, height: _G.packH,
        fit: BoxFit.fill, gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink());
    if (brightness != null) {
      img = ColorFiltered(
        colorFilter: ColorFilter.matrix([
          brightness!, 0, 0, 0, 0,
          0, brightness!, 0, 0, 0,
          0, 0, brightness!, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    return SizedBox(
      width: _G.packW,
      height: _G.packH,
      child: Stack(children: [
        Positioned(
          top: _G.packH * fromFrac,
          left: 0,
          width: _G.packW,
          height: _G.packH * (toFrac - fromFrac),
          child: ClipRect(
            child: OverflowBox(
              maxWidth: _G.packW,
              maxHeight: _G.packH,
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: Offset(0, -_G.packH * fromFrac),
                child: img,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 입구 뒷벽 띠(11.3~14%, 어둡게) + 슬롯 암부 — 카드 **뒤**.
class _PackBack extends StatelessWidget {
  final double cutP;
  const _PackBack({required this.cutP});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const _AssetSlice(
        asset: 'assets/oripa/packs/navy/open_body.png',
        fromFrac: .113, toFrac: .14, brightness: .55,
      ),
      // 슬롯 암부 (립 바로 위) — 절취 진행을 따라 노출
      Positioned(
        left: _G.packW * .192, right: _G.packW * .192,
        top: _G.packH * .116, height: _G.packH * .026,
        child: Opacity(
          opacity: cutP,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xD9000000)],
                stops: [0, .7],
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// 랩퍼 앞면(14%~) + 찢긴 립 하이라이트 + 하단 브랜딩(§3-7 배치).
class _PackFront extends StatelessWidget {
  final String title;
  const _PackFront({required this.title});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const _AssetSlice(
        asset: 'assets/oripa/packs/navy/open_body.png',
        fromFrac: .14, toFrac: 1,
      ),
      // 찢긴 포일 림 (불규칙 점선 하이라이트)
      Positioned(
        left: _G.packW * .195, right: _G.packW * .195,
        top: _G.packH * .14 - 1, height: 1.5,
        child: CustomPaint(painter: _LipRimPainter()),
      ),
      Positioned(
        top: _G.packH * .62, left: 0, right: 0,
        child: Text('POKEFOLIO',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFFE9D9A8),
              fontSize: _G.packW * .052 * .66,
              fontWeight: FontWeight.w800,
              letterSpacing: _G.packW * .02 * .66,
            )),
      ),
      Positioned(
        top: _G.packH * .715, left: _G.packW * .13, right: _G.packW * .13,
        child: Text(title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .95),
              fontSize: _G.packW * .056 * .66,
              fontWeight: FontWeight.w800,
              height: 1.12,
            )),
      ),
    ]);
  }
}

class _LipRimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..strokeWidth = 1.5;
    double x = 0;
    final seg = [5.0, 3.0, 5.0]; // 밝음/어둠/중간 반복 — 불규칙 포일 단면
    final al = [.7, .22, .55];
    var i = 0;
    while (x < size.width) {
      p.color = const Color(0xFFEBF0F8).withValues(alpha: al[i % 3]);
      canvas.drawLine(Offset(x, .75), Offset(x + seg[i % 3], .75), p);
      x += seg[i % 3];
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _LipRimPainter old) => false;
}

/// 카드 뒷면 — 런타임 드로잉 (LOCKED §3-7: 자산에 굽지 않음).
class _CardBack extends StatelessWidget {
  final bool rim;
  final double glow, sheenP;
  const _CardBack({required this.rim, required this.glow, required this.sheenP});

  static const baseShadow = [
    BoxShadow(color: Color(0x80000000), blurRadius: 22, offset: Offset(0, 8)),
  ];
  static const rimShadow = [
    BoxShadow(color: Color(0x8CFFFAE2), blurRadius: 0, spreadRadius: 1),
    BoxShadow(color: Color(0x80FFF1AC), blurRadius: 6, spreadRadius: 1),
    BoxShadow(color: Color(0x47FDDC64), blurRadius: 14, spreadRadius: 3),
    BoxShadow(color: Color(0x80000000), blurRadius: 26, offset: Offset(0, 10)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF26385E), Color(0xFF111D38), Color(0xFF1F2F52)],
          stops: [0, .55, 1],
        ),
        boxShadow: rim ? rimShadow : baseShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(alignment: Alignment.center, children: [
        // 이동 sheen (리빌 중 쓸고 지나감 — 런타임 레이어)
        Positioned.fill(
          child: Align(
            alignment: Alignment(-1 + 2 * sheenP.clamp(0.0, 1.0), 0),
            child: FractionallySizedBox(
              widthFactor: .55,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft, end: Alignment.centerRight,
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: .12),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // 상단 하이라이트 라인
        Positioned(
          top: 0, left: _G.cardW * .08, right: _G.cardW * .08, height: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: .4),
                Colors.white.withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFE9D9A8).withValues(alpha: .35),
                    width: 1.2),
              ),
            ),
          ),
        ),
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: const Color(0xFFE9D9A8).withValues(alpha: .55),
                width: 1.5),
          ),
          alignment: Alignment.center,
          child: const Text('P',
              style: TextStyle(
                  color: Color(0xFFE9D9A8),
                  fontSize: 30,
                  fontWeight: FontWeight.w900)),
        ),
        Positioned(
          left: 0, right: 0, bottom: _G.cardH * .14,
          child: Text('POKEFOLIO',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .5),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.2,
              )),
        ),
      ]),
    );
  }
}

// ═══════════ 배경 발광/입자 페인터 (additive) ═══════════
class _BackFxPainter extends CustomPainter {
  final _Frame f;
  final bool hit;
  _BackFxPainter(this.f, this.hit);

  static final _rnd = _Mul32(20260714);
  static final List<_Dust> dust = List.generate(110, (_) => _Dust(_rnd));
  static final List<_Smoke> smoke = _Smoke.emitters(_Mul32(4242));
  static final List<_Boke> boke = _Boke.tiers(_Mul32(777));
  static final List<_SparkP> sparks = List.generate(26, (_) => _SparkP(_rnd));

  @override
  void paint(Canvas canvas, Size size) {
    final dim = 1 - f.blackP * .9;
    final paint = Paint()..blendMode = BlendMode.plus;
    // 아우라 후방 글로우 (카드 정중앙 뒤 top37%) — 점화 스케일
    final aur = f.auraP * (1 - f.blackP) * (f.cardOn ? 1 : 0);
    final glowBoost = _c(f.heroP > 0 && !f.cardOn ? .0 : aur);
    if (glowBoost > 0.01) {
      final ign = math.min(1.0, f.auraP * 1.15);
      final c = Offset(_G.stW / 2, _G.stH * .37);
      _radial(canvas, c, 235 * (.6 + .4 * ign) * (1 + .04 * f.pulse),
          const Color(0xFFFCDC5A), .26 * glowBoost * (1 + .35 * f.pulse), paint);
      _radial(canvas, c, 160 * (.35 + .65 * ign) * (1 + .06 * f.pulse),
          const Color(0xFFFFF4C4), .30 * glowBoost * (1 + .33 * f.pulse), paint);
    }
    // 리빌 잔광 (경로 공통, 은은)
    final g = _revealGlow();
    if (g > 0.01 && f.blackP < 1) {
      _radial(canvas, Offset(_G.stW / 2, _G.cardCy), 200,
          const Color(0xFFFCDC5A), .10 * g * (1 - f.blackP), paint);
    }
    // 컷 스파크 (절취점)
    if (f.cutP > .01 && f.cutP < 1) {
      final hx = _G.packX + (_G.packW - _G.mouthW) / 2 + _G.mouthW * f.cutP;
      final hy = _G.packY + f.bob + _G.mouthH;
      for (final p in sparks) {
        final lt = (f.cutP * 3.2 + p.ph) % 1;
        final a = (1 - lt) * .85 * dim;
        if (a <= .01) continue;
        paint.color = const Color(0xFFFFF0BE).withValues(alpha: _c(a));
        canvas.drawCircle(
            Offset(hx + p.dx * p.v * lt * .9 - _G.mouthW * .12 * lt,
                hy + p.dy * p.v * lt),
            p.r * (1 - lt * .5), paint);
      }
      // 컷 트레일(헤드 뒤 73px) + 헤드 글로우
      final trail = math.min(73.0, _G.mouthW * f.cutP);
      final rect = Rect.fromLTWH(hx - trail, hy - 1.5, trail, 3);
      paint.shader = LinearGradient(colors: [
        const Color(0x00FFF6D2),
        const Color(0xFFFFF6D2).withValues(alpha: .9 * dim),
      ]).createShader(rect);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
      paint.shader = null;
      _radial(canvas, Offset(hx, hy), 16, Colors.white, .9 * dim, paint);
    }
    // 금빛 먼지 (상시 은은 → 리빌 후 강화)
    final dustA = (.10 + .30 * _revealGlow() + (aur > 0 ? .10 : 0)) * dim;
    if (dustA > .01) {
      for (final p in dust) {
        final tw = .4 + .6 * (math.sin(f.t / 700 * p.w + p.ph)).abs();
        var y = (p.y - f.t / 1000 * p.dy) % _G.stH;
        if (y < 0) y += _G.stH;
        paint.color =
            const Color(0xFFE9D9A8).withValues(alpha: _c(dustA * tw * .55));
        canvas.drawCircle(Offset(p.x, y), p.r, paint);
      }
    }
    // 스멀스멀 연기 + 3단계 보케 (아우라 점화 40% 이후)
    final k = aur * _c((f.auraP - .4) / .6);
    if (k > .01) {
      final cc = Offset(_G.stW / 2, _G.cardCy);
      for (final s in smoke) {
        final p = ((f.t / s.life) + s.ph) % 1;
        final env = math.pow(math.sin(math.pi * p), 1.15).toDouble();
        final a = k * s.a0 * env;
        if (a <= .008) continue;
        final x = cc.dx + s.ex + s.drift * p +
            s.sway * math.sin(p * s.swf * 2 * math.pi + s.sph) * (.35 + p);
        final y = cc.dy + s.ey - s.rise * p;
        final r = s.s0 * (.55 + 1.9 * p);
        _radial(canvas, Offset(x, y), r,
            s.warm ? const Color(0xFFFFDE84) : const Color(0xFFFFF2C4), a, paint);
      }
      for (final b in boke) {
        final tw = math.max(0.0, math.sin(f.t / 1100 * b.sp + b.ph));
        final a = k * tw * (b.soft ? .28 : .7);
        if (a <= .02) continue;
        final o = Offset(cc.dx + b.ox, cc.dy + b.oy + math.sin(f.t / 1500 + b.ph) * 8);
        if (b.soft) {
          _radial(canvas, o, b.sz * 2.2 * (.5 + .5 * tw),
              const Color(0xFFFFEEAF), a, paint);
        } else {
          paint.color = const Color(0xFFFFEEAF).withValues(alpha: _c(a));
          canvas.drawCircle(o, b.sz * (.5 + .5 * tw), paint);
        }
      }
    }
  }

  double _revealGlow() => _c((f.slideP - .1) / .9);
  static double _c(double v) => v.clamp(0.0, 1.0);

  void _radial(Canvas canvas, Offset c, double r, Color color, double alpha,
      Paint paint) {
    if (alpha <= 0) return;
    paint.shader = RadialGradient(colors: [
      color.withValues(alpha: _c(alpha)),
      color.withValues(alpha: _c(alpha) * .35),
      color.withValues(alpha: 0),
    ], stops: const [0, .45, 1])
        .createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, paint);
    paint.shader = null;
  }

  @override
  bool shouldRepaint(covariant _BackFxPainter old) => true;
}

// ═══════════ 전면 페인터 — 옆면 선광 · 코어 · 링 · 플래시(비네트) ═══════════
class _FrontFxPainter extends CustomPainter {
  final _Frame f;
  _FrontFxPainter(this.f);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..blendMode = BlendMode.plus;
    final cx = _G.stW / 2;
    // 옆면 선광 (위아래 감쇠 + 회전방향 잔상)
    if (f.edgeF > .01) {
      _vline(canvas, cx - 10 - 6 * f.edgeF, _G.cardCy, 300, 2, .35 * f.edgeF, 4, paint);
      _vline(canvas, cx, _G.cardCy, 330, 3, f.edgeF, 1, paint);
    }
    // 흰 코어
    if (f.coreP > .01 && f.flashP < 1) {
      final a = f.coreP * (1 - f.heroP);
      _radialP(canvas, Offset(cx, _G.stH / 2), 32 * (.4 + .6 * f.coreP),
          Colors.white, a, paint);
    }
    // 얇은 금 링 확장
    if (f.ringP > .01 && f.ringP < 1) {
      paint.shader = null;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;
      paint.color =
          const Color(0xFFFFE9A0).withValues(alpha: ((1 - f.ringP) * .9).clamp(0.0, 1.0));
      canvas.drawCircle(
          Offset(cx, _G.stH / 2), 90 * (.25 + 2.3 * f.ringP), paint);
      paint.style = PaintingStyle.fill;
    }
    // 백금 플래시 — 중심 밝고 가장자리 비네트 유지
    if (f.flashP > .01) {
      paint.shader = RadialGradient(colors: [
        const Color(0xFFFDFBF4).withValues(alpha: (f.flashP * .95).clamp(0.0, 1.0)),
        const Color(0xFFFDFAF2).withValues(alpha: (f.flashP * .76).clamp(0.0, 1.0)),
        const Color(0x00FDFAF2),
      ], stops: const [0, .42, 1])
          .createShader(Rect.fromCenter(
              center: Offset(cx, _G.stH * .47),
              width: _G.stW * 1.12,
              height: _G.stH * 1.04));
      canvas.drawRect(Offset.zero & size, paint);
      paint.shader = null;
    }
  }

  void _vline(Canvas canvas, double x, double cy, double h, double w,
      double alpha, double blur, Paint paint) {
    final rect = Rect.fromCenter(center: Offset(x, cy), width: w, height: h);
    paint.shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [
        const Color(0x00FFF6D2),
        const Color(0xFFFFF6D2).withValues(alpha: (alpha * .35).clamp(0.0, 1.0)),
        Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0)),
        const Color(0xFFFFF6D2).withValues(alpha: (alpha * .35).clamp(0.0, 1.0)),
        const Color(0x00FFF6D2),
      ],
      stops: const [0, .18, .5, .82, 1],
    ).createShader(rect);
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    paint.maskFilter = null;
    paint.shader = null;
  }

  void _radialP(Canvas canvas, Offset c, double r, Color color, double alpha,
      Paint paint) {
    paint.shader = RadialGradient(colors: [
      color.withValues(alpha: alpha.clamp(0.0, 1.0)),
      color.withValues(alpha: (alpha * .4).clamp(0.0, 1.0)),
      color.withValues(alpha: 0),
    ], stops: const [0, .4, 1])
        .createShader(Rect.fromCircle(center: c, radius: r * 3));
    canvas.drawCircle(c, r * 3, paint);
    paint.shader = null;
  }

  @override
  bool shouldRepaint(covariant _FrontFxPainter old) => true;
}

// ── 결정론 입자 파라미터 ──
class _Mul32 {
  int _a;
  _Mul32(this._a);
  double call() {
    _a = (_a + 0x6D2B79F5) & 0xFFFFFFFF;
    var x = _a ^ (_a >>> 15);
    x = (x * (1 | _a)) & 0xFFFFFFFF;
    x = (x + ((x ^ (x >>> 7)) * (61 | x) & 0xFFFFFFFF)) ^ x;
    return ((x ^ (x >>> 14)) & 0xFFFFFFFF) / 4294967296;
  }
}

class _Dust {
  late final double x, y, r, w, ph, dy;
  _Dust(_Mul32 rnd) {
    x = rnd() * _G.stW; y = rnd() * _G.stH;
    r = .5 + rnd() * 1.5; w = .4 + rnd() * 1.4;
    ph = rnd() * 6.28; dy = 2 + rnd() * 8;
  }
}

class _SparkP {
  late final double dx, dy, v, r, ph;
  _SparkP(_Mul32 rnd) {
    dx = (rnd() - .5) * 2; dy = -(.2 + rnd() * .9);
    v = 30 + rnd() * 80; r = .7 + rnd() * 1.3; ph = rnd();
  }
}

class _Smoke {
  final double ex, ey, life, ph, rise, sway, swf, sph, s0, drift, a0;
  final bool warm;
  _Smoke(this.ex, this.ey, this.life, this.ph, this.rise, this.sway, this.swf,
      this.sph, this.s0, this.drift, this.a0, this.warm);

  static List<_Smoke> emitters(_Mul32 r) {
    final hw = _G.cardW * 1.08 / 2, hh = _G.cardH * 1.08 / 2;
    final em = [
      [-hw - 2, -hh * .55], [-hw - 2, .15 * hh], [-hw + 6, hh * .8],
      [hw + 2, -hh * .55], [hw + 2, .15 * hh], [hw - 6, hh * .8],
      [-hw * .55, -hh - 4], [hw * .55, -hh - 4],
    ];
    final out = <_Smoke>[];
    for (final e in em) {
      for (var j = 0; j < 6; j++) {
        out.add(_Smoke(e[0], e[1], 2600 + r() * 1500, r(), 70 + r() * 70,
            9 + r() * 16, .6 + r() * .9, r() * 6.28, 11 + r() * 15,
            (r() - .5) * 14, .15 + r() * .10, r() < .6));
      }
    }
    return out;
  }
}

class _Boke {
  final double ox, oy, sz, sp, ph;
  final bool soft;
  _Boke(this.ox, this.oy, this.sz, this.sp, this.ph, this.soft);

  static List<_Boke> tiers(_Mul32 r) {
    final out = <_Boke>[];
    for (var i = 0; i < 5; i++) {
      out.add(_Boke((r() - .5) * 260, (r() - .5) * 320, 3 + r() * 2.6,
          .5 + r() * .5, r() * 6.28, true)); // 가까운 큰 보케
    }
    for (var i = 0; i < 10; i++) {
      out.add(_Boke((r() - .5) * 330, (r() - .5) * 420, 1.2 + r() * 1.6,
          .8 + r() * .9, r() * 6.28, false));
    }
    for (var i = 0; i < 16; i++) {
      out.add(_Boke((r() - .5) * 380, (r() - .5) * 480, .6 + r() * .9,
          1.1 + r() * 1.4, r() * 6.28, false)); // 먼 작은 다수
    }
    return out;
  }
}
