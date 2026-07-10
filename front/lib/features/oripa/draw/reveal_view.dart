import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../oripa_common.dart';
import '../data/oripa_prizes.dart';
import '../data/reveal_models.dart';

/// 그레이딩 슬랩 프레임 — 카드 이미지를 투명 슬랩 + 회사/등급 라벨로 감쌈.
/// (별도 슬랩 이미지 파일 대신 Flutter 컴포넌트 — PSA/BRG 프로파일 공용, GPT 방식.)
class SlabFrame extends StatelessWidget {
  final ImageRef imageRef;
  final String company; // BRG / PSA
  final String grade; // "10"
  const SlabFrame({
    super.key,
    required this.imageRef,
    required this.company,
    required this.grade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 36, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1.5),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 186,
              height: 260,
              child: OripaPrizeImage(imageRef: imageRef),
            ),
          ),
          Positioned(
            top: -28,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.blue,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text('$company  $grade',
                  key: const Key('slab_label'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 상품 HERO — GRADED=슬랩 프레임 / RAW·PACK·GOODS=이미지.
Widget buildHeroContent(OripaPrize prize) {
  if (prize is GradedCardPrize) {
    return SlabFrame(
      imageRef: prize.imageRef,
      company: prize.gradingCompany.label,
      grade: prize.gradeValue,
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 210,
      height: 292,
      child: OripaPrizeImage(imageRef: prize.imageRef),
    ),
  );
}

/// 개봉 확정 후 결과 리빌 — 오프닝 헤더 → clue 비트(자동진행 + 탭가속) → HERO stage.
///
/// ★ markRevealStarted/markRevealed 세션 전이는 **draw 화면이 배선**(타이밍 계약):
///   - draw 화면이 [N번 상품 확인하기] 즉시 markRevealStarted 후 이 위젯 mount
///   - [onHeroShown] (HERO 실제 렌더 후) → draw 화면이 markRevealed(drawId)
///   - [onResultReady] (heroHold 종료) → draw 화면이 결과 액션 표시
class RevealView extends StatefulWidget {
  final RevealDescriptor descriptor;
  final RevealConfig config;
  final Widget hero;
  final bool startAtHero; // 재진입: clue 생략, HERO부터
  final bool skipHold; // REVEALED 재진입: heroHold 재실행 안 함
  final VoidCallback onHeroShown;
  final VoidCallback onResultReady;
  const RevealView({
    super.key,
    required this.descriptor,
    required this.config,
    required this.hero,
    required this.onHeroShown,
    required this.onResultReady,
    this.startAtHero = false,
    this.skipHold = false,
  });

  @override
  State<RevealView> createState() => _RevealViewState();
}

class _RevealViewState extends State<RevealView> {
  static const int _opening = -1;
  late int _beat; // -1=오프닝 헤더, 0..n-1=clue 비트, n=HERO
  bool _heroDone = false;
  Timer? _timer;

  int get _heroBeat => widget.descriptor.clues.length;

  @override
  void initState() {
    super.initState();
    if (widget.startAtHero) {
      _beat = _heroBeat; // clue 생략, HERO 즉시
      WidgetsBinding.instance.addPostFrameCallback((_) => _heroRendered());
    } else {
      _beat = _opening;
      _timer =
          Timer(Duration(milliseconds: widget.config.openingLockMs), _next);
    }
  }

  void _next() {
    _timer?.cancel();
    if (_beat >= _heroBeat) return;
    setState(() => _beat = _beat + 1);
    if (_beat >= _heroBeat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _heroRendered());
    } else {
      _timer = Timer(
          Duration(
              milliseconds: widget.config.beatDwellMs +
                  widget.config.pauseBetweenBeatsMs),
          _next);
    }
  }

  void _heroRendered() {
    if (!mounted || _heroDone) return;
    _heroDone = true;
    widget.onHeroShown(); // HERO 실제 렌더 후 → draw 화면이 markRevealed
    if (widget.skipHold) {
      widget.onResultReady();
    } else {
      _timer = Timer(Duration(milliseconds: widget.config.heroHoldMinMs), () {
        if (mounted) widget.onResultReady();
      });
    }
  }

  void _onTap() {
    if (_beat <= _opening) return; // 오프닝 락 — 탭 무시
    if (_beat >= _heroBeat) return; // HERO — 탭 무시(heroHold 단축 불가)
    _next(); // 현재 clue 완료 → 다음(비트당 1회 가속)
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.config.tapAdvance ? _onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: _beat >= _heroBeat ? widget.hero : _cluePanel(),
      ),
    );
  }

  Widget _cluePanel() {
    final d = widget.descriptor;
    final clue =
        (_beat >= 0 && _beat < d.clues.length) ? d.clues[_beat].text : '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (d.openingHeader != null)
          Text(d.openingHeader!, style: AppText.caption),
        const SizedBox(height: 16),
        Text(
          clue,
          key: const Key('reveal_clue'),
          style: const TextStyle(
              color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}
