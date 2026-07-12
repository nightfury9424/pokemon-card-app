import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../oripa_common.dart';
import '../data/oripa_mock.dart';
import '../data/oripa_session.dart';
import '../data/reveal_models.dart';
import 'oripa_sealed_pack.dart';
import 'reveal_view.dart';

/// 뽑기 풀스크린 — route `extra`=drawId만. 번호·상품·descriptor는 **session.activeDraw**에서만 읽음.
/// extracting → peeling → [상품 확인하기] → revealing(RevealView) → result(보관/교환) — 화면 내부 완결.
/// 재진입: COMMITTED+!revealStarted=개봉 / COMMITTED+revealStarted=committedRecovery /
///        REVEALED=revealedRecovery / RESOLVED=clear·복귀. 불일치 drawId=애니 없이 안전 복귀.
class OripaDrawScreen extends StatefulWidget {
  final String oripaId;
  final String drawId;
  const OripaDrawScreen({super.key, required this.oripaId, required this.drawId});

  @override
  State<OripaDrawScreen> createState() => _OripaDrawScreenState();
}

enum _Stage { extracting, peeling, numberDone, revealing, result, invalid }

class _OripaDrawScreenState extends State<OripaDrawScreen>
    with TickerProviderStateMixin {
  OripaSession get _s => OripaSession.instance;
  ActiveDraw? _draw;
  _Stage _stage = _Stage.invalid;
  RevealEntryMode _entryMode = RevealEntryMode.fresh;

  late final AnimationController _extract;
  late final AnimationController _coverOut;
  final ValueNotifier<double> _progress = ValueNotifier(0);
  final ValueNotifier<double> _tilt = ValueNotifier(0);
  bool _hz60 = false, _hz82 = false;

  // 추출 시작 게이팅 — route 전환(fade) completed 후 exactly-once forward.
  Animation<double>? _routeAnim;
  Timer? _extractTimer;
  bool _extractStarted = false;

  bool _resolved = false; // 보관/교환 완료 → 시스템 back 허용
  bool _acting = false; // 보관/교환 연타 차단
  bool _exitHandled = false;

  // 상단 절취 가로 드래그 완료까지의 참조 거리(px). 팩 크기는 OripaSealedPack가 소유.
  static const double _tearDist = 220;

  bool get _reduceMotion =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
          .disableAnimations;

  @override
  void initState() {
    super.initState();
    _extract = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _reduceMotion ? 0 : 900))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed && mounted) {
          setState(() => _stage = _Stage.peeling);
        }
      });
    _coverOut = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _reduceMotion ? 0 : 360));

    // ── 3조건 검증 (activeDraw 존재 + drawId + oripaId) ──
    final a = _s.activeDraw;
    if (a == null || a.drawId != widget.drawId || a.oripaId != widget.oripaId) {
      _stage = _Stage.invalid;
      WidgetsBinding.instance.addPostFrameCallback((_) => _safeReturn());
      return;
    }
    _draw = a;
    switch (a.status) {
      case DrawStatus.committed:
        if (a.revealStarted) {
          _stage = _Stage.revealing;
          _entryMode = RevealEntryMode.committedRecovery;
        } else {
          _stage = _Stage.extracting;
          _entryMode = RevealEntryMode.fresh;
          _armExtractStart(); // route 전환 completed 후 시작(겹침 방지)
        }
      case DrawStatus.revealed:
        _stage = _Stage.revealing;
        _entryMode = RevealEntryMode.revealedRecovery;
      case DrawStatus.resolved:
        _stage = _Stage.invalid; // 완료된 draw → clear·복귀
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _s.clearActiveDraw(widget.drawId);
          _safeReturn();
        });
    }
  }

  @override
  void dispose() {
    _extractTimer?.cancel();
    _routeAnim?.removeStatusListener(_onRouteAnimStatus);
    _extract.dispose();
    _coverOut.dispose();
    _progress.dispose();
    _tilt.dispose();
    // 방어적: RESOLVED만 내부 clear. 네비게이션 호출 안 함.
    _s.clearActiveDraw(widget.drawId);
    super.dispose();
  }

  // ── 통일 종료 ──
  void _safeReturn() {
    if (_exitHandled) return;
    _exitHandled = true;
    if (mounted) context.pop();
  }

  void _finishAndExit([String? result]) {
    if (_exitHandled) return;
    _exitHandled = true;
    _s.clearActiveDraw(widget.drawId); // RESOLVED만 clear(내부 가드)
    if (mounted) context.pop(result);
  }

  // ── 추출 시작 게이팅 — 고정 딜레이로 정착을 "추정"하지 않는다.
  //    /oripa/draw route 전환 애니가 실제 completed된 뒤 +100ms에 exactly-once forward.
  //    route animation이 null(전환 없음)이거나 이미 completed면 곧바로 스케줄.
  void _armExtractStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stage != _Stage.extracting) return;
      final anim = ModalRoute.of(context)?.animation;
      if (anim == null || anim.status == AnimationStatus.completed) {
        _scheduleExtract(); // 전환 없음/이미 정착 → 바로
      } else {
        _routeAnim = anim..addStatusListener(_onRouteAnimStatus);
      }
    });
  }

  void _onRouteAnimStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _routeAnim?.removeStatusListener(_onRouteAnimStatus);
    _routeAnim = null;
    _scheduleExtract();
  }

  void _scheduleExtract() {
    if (_extractStarted || !mounted || _stage != _Stage.extracting) return;
    final delay =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 100);
    _extractTimer?.cancel();
    _extractTimer = Timer(delay, () {
      if (_extractStarted || !mounted || _stage != _Stage.extracting) return;
      _extractStarted = true;
      _extract.forward();
    });
  }

  // ── 상단 절취(개봉) — 상단 탭을 가로로 당김. dx=절취 진행, dy=미세 기울기. ──
  void _onDrag(DragUpdateDetails d) {
    if (_stage != _Stage.peeling) return;
    final next = (_progress.value + d.delta.dx / _tearDist).clamp(0.0, 1.0);
    if (next > _progress.value) _progress.value = next;
    _tilt.value = (_tilt.value + d.delta.dy * 0.02).clamp(-1.5, 1.5);
    _haptics();
    if (_progress.value >= 0.82) _completePeel();
  }

  void _onDragEnd(DragEndDetails _) {
    if (_stage != _Stage.peeling) return;
    if (_progress.value < 0.05) _progress.value = 0;
    _tilt.value = 0;
  }

  void _haptics() {
    if (!_hz60 && _progress.value >= 0.60) {
      _hz60 = true;
      HapticFeedback.lightImpact();
    }
    if (!_hz82 && _progress.value >= 0.82) {
      _hz82 = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _completePeel() {
    if (_stage == _Stage.numberDone) return;
    setState(() => _stage = _Stage.numberDone);
    final start = _progress.value;
    _coverOut
      ..addListener(() {
        _progress.value = start + (1.0 - start) * _coverOut.value;
      })
      ..forward();
  }

  // ── [상품 확인하기] → 리빌 진입 (markRevealStarted 즉시) ──
  void _confirmPrize() {
    _s.markRevealStarted(widget.drawId); // ★애니/await 前 즉시 기록
    setState(() {
      _stage = _Stage.revealing;
      _entryMode = RevealEntryMode.fresh;
    });
  }

  // ── 결과 액션 ──
  void _keep() {
    if (_acting || _resolved) return;
    _acting = true;
    _s.keepPrize(widget.drawId, OripaMock.oripaById(widget.oripaId).shopId);
    _applyResolution(DrawResolution.keep);
  }

  void _exchange() {
    if (_acting || _resolved) return;
    _acting = true;
    _s.exchangePrize(widget.drawId);
    _applyResolution(DrawResolution.exchange);
  }

  /// 세션이 실제로 이 draw를 RESOLVED+기대 resolution으로 처리했을 때만 완료 UI로 전환.
  /// (drawId 불일치·상태 거부 시 완료 처리·back 허용 안 함, _acting 해제 후 재시도 가능.)
  void _applyResolution(DrawResolution expected) {
    final a = _s.activeDraw;
    final ok = a != null &&
        a.drawId == widget.drawId &&
        a.status == DrawStatus.resolved &&
        a.resolution == expected;
    if (!mounted) return;
    setState(() {
      _resolved = ok;
      _acting = false;
    });
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('처리에 실패했습니다. 다시 시도해 주세요.'),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _resolved || _stage == _Stage.invalid,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // 시스템 back(허용됨=RESOLVED) → clear
          _s.clearActiveDraw(widget.drawId);
          _exitHandled = true;
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text('뽑기가 진행 중입니다. 결과를 확인한 뒤 이동할 수 있습니다.'),
              behavior: SnackBarBehavior.floating,
            ));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_draw == null) return const SizedBox.shrink();
    switch (_stage) {
      case _Stage.invalid:
        return const SizedBox.shrink();
      case _Stage.extracting:
      case _Stage.peeling:
      case _Stage.numberDone:
        return _peelFlow();
      case _Stage.revealing:
        return RevealView(
          descriptor: _draw!.revealDescriptor,
          config: RevealConfig(reduceMotion: _reduceMotion),
          hero: buildHeroContent(_draw!.prize),
          entryMode: _entryMode,
          onHeroShown: () => _s.markRevealed(widget.drawId), // HERO 렌더 후
          onResultReady: () {
            if (mounted) setState(() => _stage = _Stage.result);
          },
        );
      case _Stage.result:
        return _resultView();
    }
  }

  // ── 개봉 플로우 (추출→peel→번호→[상품 확인하기]) ──
  Widget _peelFlow() {
    final remaining = _s.remaining(OripaMock.oripaById(widget.oripaId));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('남은 $remaining구', style: AppText.caption),
          ),
        ),
        Expanded(
          child: Center(
            child: _stage == _Stage.extracting ? _buildExtract() : _buildTear(),
          ),
        ),
        SizedBox(height: 96, child: Center(child: _peelFooter())),
      ],
    );
  }

  Widget _peelFooter() {
    if (_stage == _Stage.numberDone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OripaPrimaryButton(
          label: '${_draw!.number}번 상품 확인하기',
          onTap: _confirmPrize,
        ),
      );
    }
    if (_stage == _Stage.peeling) {
      return Text('상단 탭을 옆으로 당겨 개봉하세요', style: AppText.muted);
    }
    return const SizedBox.shrink();
  }

  // ── 결과 액션(화면 내부 완결) ──
  Widget _resultView() {
    final prize = _draw!.prize;
    return Column(
      children: [
        const SizedBox(height: 24),
        Expanded(child: Center(child: buildHeroContent(prize))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            children: [
              Text('${_draw!.number}번 상품 · ${prize.displayName}',
                  style: AppText.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('교환 ${formatPoint(prize.exchangePoints)}',
                  style: AppText.bodyStrong),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: _resolved
              ? Row(children: [
                  Expanded(
                      child: _actionButton('오리파로 돌아가기',
                          filled: false, onTap: () => _finishAndExit())),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _actionButton('다시 뽑기',
                          filled: true, onTap: () => _finishAndExit('again'))),
                ])
              : Row(children: [
                  Expanded(
                      child:
                          _actionButton('보관하기', filled: false, onTap: _keep)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _actionButton(
                          '${formatPoint(prize.exchangePoints)}로 교환',
                          filled: true,
                          onTap: _exchange)),
                ]),
        ),
      ],
    );
  }

  Widget _actionButton(String label,
      {required bool filled, required VoidCallback onTap}) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppColors.blue : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(label,
            style: TextStyle(
                color: filled ? Colors.white : AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── 추출: route 정착 후 팩 등장. 중심 이동 없음 — scale은 center 기준 →
  //    추출 시작/완료 중심좌표 동일(구형 translate +60 점프 제거). ──
  Widget _buildExtract() {
    return AnimatedBuilder(
      animation: _extract,
      builder: (_, _) {
        final t = Curves.easeOutCubic.transform(_extract.value);
        // translate 금지: fade + center-anchored scale만.
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.96 + t * 0.04, // 0.96 → 1.00
            child: _pack(tearProgress: 0),
          ),
        );
      },
    );
  }

  // ── 상단 절취: 상단 탭을 가로로 당김(60·82% 햅틱). 팩 몸체 중심은 고정. ──
  Widget _buildTear() {
    return GestureDetector(
      onHorizontalDragUpdate: _onDrag,
      onHorizontalDragEnd: _onDragEnd,
      behavior: HitTestBehavior.opaque,
      child: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (_, p, _) => ValueListenableBuilder<double>(
          valueListenable: _tilt,
          builder: (_, deg, _) => _pack(tearProgress: p, tilt: deg),
        ),
      ),
    );
  }

  // 추출·절취 공용 봉인팩(동일 크기·동일 중심 anchor). 아우라·뒷면 상승은 Step 2.
  OripaSealedPack _pack({required double tearProgress, double tilt = 0}) =>
      OripaSealedPack(
        title: OripaMock.oripaById(widget.oripaId).title,
        number: _draw!.number,
        tearProgress: tearProgress,
        tilt: tilt,
      );
}
