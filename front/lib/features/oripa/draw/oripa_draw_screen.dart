import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../oripa_common.dart';
import '../data/oripa_mock.dart';
import '../data/oripa_session.dart';

/// 뽑기 풀스크린 — 봉인더미 자동추출 → 덮개 까기 → 번호 확인 → [상품 확인하기].
/// result는 확인시트에서 confirmDraw로 이미 확정되어 extra로 전달됨(난수/애니중결정 없음).
/// 결과 확인 전 뒤로가기 차단(PopScope). 종료는 [상품 확인하기]의 imperative pop만.
class OripaDrawScreen extends StatefulWidget {
  final String oripaId;
  final DrawResult result;
  const OripaDrawScreen({super.key, required this.oripaId, required this.result});

  @override
  State<OripaDrawScreen> createState() => _OripaDrawScreenState();
}

enum _Phase { extracting, peeling, revealed }

class _OripaDrawScreenState extends State<OripaDrawScreen>
    with TickerProviderStateMixin {
  late final AnimationController _extract;
  late final AnimationController _coverOut; // 82% 이후 덮개 완전 이탈(0.82→1.0)
  final ValueNotifier<double> _progress = ValueNotifier(0); // 덮개 진행률 0~1(단조)
  final ValueNotifier<double> _tilt = ValueNotifier(0); // 덮개 미세 회전(deg)

  _Phase _phase = _Phase.extracting;
  bool _hz60 = false, _hz82 = false, _showCta = false;

  static const double _cardW = 210, _cardH = 292;
  static const double _peelDist = 300; // progress 1.0 = 이만큼 드래그

  @override
  void initState() {
    super.initState();
    _extract = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() => _phase = _Phase.peeling);
        }
      });
    _coverOut = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
    _extract.forward();
  }

  @override
  void dispose() {
    _extract.dispose();
    _coverOut.dispose();
    _progress.dispose();
    _tilt.dispose();
    super.dispose();
  }

  void _onDrag(DragUpdateDetails d) {
    if (_phase != _Phase.peeling) return;
    // 아래로 단조 진행: 위로 움직여도 progress 감소 금지.
    final next = (_progress.value + d.delta.dy / _peelDist).clamp(0.0, 1.0);
    if (next > _progress.value) _progress.value = next;
    _tilt.value = (_tilt.value + d.delta.dx * 0.02).clamp(-1.2, 1.2);
    _haptics();
    if (_progress.value >= 0.82) _complete();
  }

  void _onDragEnd(DragEndDetails _) {
    if (_phase != _Phase.peeling) return;
    if (_progress.value < 0.05) _progress.value = 0; // 실수터치만 원위치
    _tilt.value = 0; // 회전만 정렬, 진행률은 유지(스프링백 없음)
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

  void _complete() {
    if (_phase == _Phase.revealed) return;
    setState(() => _phase = _Phase.revealed);
    final start = _progress.value;
    _coverOut
      ..addListener(() {
        _progress.value = start + (1.0 - start) * _coverOut.value;
      })
      ..forward().then((_) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _showCta = true);
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    final o = OripaMock.oripaById(widget.oripaId);
    final remaining = OripaSession.instance.remaining(o);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
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
        body: SafeArea(
          child: Column(
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
                  child: _phase == _Phase.extracting ? _buildExtract() : _buildPeel(),
                ),
              ),
              SizedBox(
                height: 96,
                child: Center(child: _buildFooter()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_showCta) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OripaPrimaryButton(
          label: '${widget.result.number}번 상품 확인하기',
          onTap: () => context.pop(), // imperative pop = PopScope canPop:false 우회
        ),
      );
    }
    if (_phase == _Phase.peeling) {
      return Text('덮개 카드를 아래로 천천히 내려보세요', style: AppText.muted);
    }
    return const SizedBox.shrink();
  }

  // ── 봉인물 자동 추출 (더미 겹침 → 한 장 앞으로) ──
  Widget _buildExtract() {
    return AnimatedBuilder(
      animation: _extract,
      builder: (_, _) {
        final t = Curves.easeOut.transform(_extract.value);
        return SizedBox(
          width: _cardW + 40,
          height: _cardH + 40,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < 8; i++)
                Transform.translate(
                  offset: Offset((i - 4) * 2.0, (i - 4) * -1.4),
                  child: Transform.rotate(
                    angle: (i - 4) * 0.008,
                    child: _coverCard(_cardW * 0.72, _cardH * 0.72),
                  ),
                ),
              // 추출되는 한 장
              Transform.translate(
                offset: Offset(0, t * 60),
                child: Transform.scale(
                  scale: 0.72 + t * 0.28,
                  child: Opacity(opacity: 0.5 + t * 0.5, child: _coverCard(_cardW * 0.72, _cardH * 0.72)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 덮개 까기 ──
  Widget _buildPeel() {
    return GestureDetector(
      onVerticalDragUpdate: _onDrag,
      onVerticalDragEnd: _onDragEnd,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _cardW,
        height: _cardH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 아래: 일반 RR 카드 + 흰 번호 스티커(중앙)
            Container(
              width: _cardW,
              height: _cardH,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _numberSticker(),
            ),
            // 위: 덮개 카드 — progress만큼 아래로 슬라이드(위→아래 노출)
            ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, p, _) => ValueListenableBuilder<double>(
                valueListenable: _tilt,
                builder: (_, deg, _) {
                  if (p >= 1) return const SizedBox.shrink();
                  return Transform.translate(
                    offset: Offset(0, p * _cardH),
                    child: Transform.rotate(
                      angle: deg * math.pi / 180,
                      alignment: Alignment.topCenter,
                      child: _coverCard(_cardW, _cardH, shadow: true),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberSticker() {
    // 흰 번호 스티커 = 실물 요소(디자인킷 밖 예외). 덮개가 내려가며 위→아래로 드러남.
    return Container(
      width: 104,
      height: 104,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Text('${widget.result.number}',
          style: const TextStyle(
              color: Color(0xFF141414), fontSize: 40, fontWeight: FontWeight.w900)),
    );
  }

  Widget _coverCard(double w, double h, {bool shadow = false}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        // 카드 두께/접촉 그림자(무채색) — 실물 물리감(§14). 컬러 글로우 아님.
        boxShadow: shadow
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.38),
                    blurRadius: 18,
                    offset: const Offset(0, 10)),
              ]
            : null,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.catching_pokemon,
          color: Colors.white.withValues(alpha: 0.10), size: w * 0.34),
    );
  }
}
