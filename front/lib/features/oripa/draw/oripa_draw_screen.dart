import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../data/oripa_mock.dart';
import '../data/oripa_session.dart';
import 'oripa_reveal_flow.dart';
import 'reveal_view.dart' show RevealEntryMode, buildHeroContent;

/// 뽑기 풀스크린 — route `extra`=drawId만. 번호·상품·descriptor는 **session.activeDraw**에서만 읽음.
/// gate(route 정착 대기) → flow(OripaRevealFlow: 개봉→리빌 전체, 승인 HTML v3 이식)
/// → result(보관/교환) — 화면 내부 완결.
/// 재진입: COMMITTED+!revealStarted=fresh / COMMITTED+revealStarted=committedRecovery /
///        REVEALED=revealedRecovery / RESOLVED=clear·복귀. 불일치 drawId=애니 없이 안전 복귀.
class OripaDrawScreen extends StatefulWidget {
  final String oripaId;
  final String drawId;
  const OripaDrawScreen({super.key, required this.oripaId, required this.drawId});

  @override
  State<OripaDrawScreen> createState() => _OripaDrawScreenState();
}

enum _Stage { gate, flow, result, invalid }

class _OripaDrawScreenState extends State<OripaDrawScreen> {
  OripaSession get _s => OripaSession.instance;
  ActiveDraw? _draw;
  _Stage _stage = _Stage.invalid;
  RevealEntryMode _entryMode = RevealEntryMode.fresh;

  // 시작 게이팅 — route 전환(fade) completed 후 exactly-once로 flow 시작(겹침 방지).
  Animation<double>? _routeAnim;
  Timer? _startTimer;
  bool _flowStarted = false;

  bool _resolved = false; // 보관/교환 완료 → 시스템 back 허용
  bool _acting = false; // 보관/교환 연타 차단
  bool _exitHandled = false;

  bool get _reduceMotion =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
          .disableAnimations;

  @override
  void initState() {
    super.initState();
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
          _stage = _Stage.flow; // 리플레이 없이 HERO 복구
          _entryMode = RevealEntryMode.committedRecovery;
        } else {
          _stage = _Stage.gate;
          _entryMode = RevealEntryMode.fresh;
          _armFlowStart(); // route 전환 completed 후 시작
        }
      case DrawStatus.revealed:
        _stage = _Stage.flow;
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
    _startTimer?.cancel();
    _routeAnim?.removeStatusListener(_onRouteAnimStatus);
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

  // ── 시작 게이팅 — 고정 딜레이로 정착을 "추정"하지 않는다.
  //    route 전환 애니가 실제 completed된 뒤 +100ms에 exactly-once로 flow 진입.
  void _armFlowStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stage != _Stage.gate) return;
      final anim = ModalRoute.of(context)?.animation;
      if (anim == null || anim.status == AnimationStatus.completed) {
        _scheduleFlow();
      } else {
        _routeAnim = anim..addStatusListener(_onRouteAnimStatus);
      }
    });
  }

  void _onRouteAnimStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    _routeAnim?.removeStatusListener(_onRouteAnimStatus);
    _routeAnim = null;
    _scheduleFlow();
  }

  void _scheduleFlow() {
    if (_flowStarted || !mounted || _stage != _Stage.gate) return;
    final delay =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 100);
    _startTimer?.cancel();
    _startTimer = Timer(delay, () {
      if (_flowStarted || !mounted || _stage != _Stage.gate) return;
      _flowStarted = true;
      setState(() => _stage = _Stage.flow);
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
      case _Stage.gate:
        return const SizedBox.expand(); // route fade가 덮는 짧은 구간
      case _Stage.flow:
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    '남은 ${_s.remaining(OripaMock.oripaById(widget.oripaId))}구',
                    style: AppText.caption),
              ),
            ),
            Expanded(
              child: OripaRevealFlow(
                title: OripaMock.oripaById(widget.oripaId).title,
                number: _draw!.number,
                descriptor: _draw!.revealDescriptor,
                heroFront: buildHeroContent(_draw!.prize),
                entryMode: _entryMode,
                reduceMotion: _reduceMotion,
                onRevealStarted: () =>
                    _s.markRevealStarted(widget.drawId), // ★탭 즉시 기록
                onHeroShown: () =>
                    _s.markRevealed(widget.drawId), // 앞면/HERO 완전 노출 후
                onResultReady: () {
                  if (mounted) setState(() => _stage = _Stage.result);
                },
              ),
            ),
          ],
        );
      case _Stage.result:
        return _resultView();
    }
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
}
