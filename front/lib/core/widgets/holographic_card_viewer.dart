import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'card_image.dart';

/// 카드 풀스크린 뷰어 — pan으로 3D tilt + 홀로그램 빛 반사.
/// 4차-Round4 카드 hero 입체 효과 (Pokemon TCG holographic 시뮬레이션).
///
/// 사용:
/// ```
/// Navigator.push(context, PageRouteBuilder(
///   opaque: false,
///   barrierDismissible: true,
///   pageBuilder: (_, __, ___) => HolographicCardViewer(
///     imageUrl: imageUrl,
///     heroTag: 'card-${cardId}',
///     rarity: rarity,
///   ),
/// ));
/// ```
class HolographicCardViewer extends StatefulWidget {
  final String? imageUrl;
  final String? cdnFallbackUrl;
  final String heroTag;
  final String rarity;

  const HolographicCardViewer({
    super.key,
    required this.heroTag,
    required this.rarity,
    this.imageUrl,
    this.cdnFallbackUrl,
  });

  @override
  State<HolographicCardViewer> createState() => _HolographicCardViewerState();
}

class _HolographicCardViewerState extends State<HolographicCardViewer>
    with TickerProviderStateMixin {
  // -1.0~1.0 범위, pan 위치
  double _tiltX = 0;
  double _tiltY = 0;

  late final AnimationController _entryCtrl;
  late final AnimationController _restCtrl;
  Animation<double>? _restX;
  Animation<double>? _restY;

  // 레어도별 강도 — premium은 강하게
  static const _premium = {'MUR', 'UR', 'SAR', 'AR', 'MA', 'BWR', 'SSR', 'CSR', 'CHR'};
  double get _intensity => _premium.contains(widget.rarity) ? 1.0 : 0.55;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _restCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _restCtrl.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    _restCtrl.stop();
    setState(() {
      _tiltX = (_tiltX + details.delta.dx / size.width * 2.4).clamp(-1.0, 1.0);
      _tiltY = (_tiltY - details.delta.dy / size.height * 2.4).clamp(-1.0, 1.0);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // 스프링 백 — 0,0으로 부드럽게 돌아옴
    _restX = Tween(begin: _tiltX, end: 0.0).animate(
      CurvedAnimation(parent: _restCtrl, curve: Curves.elasticOut),
    );
    _restY = Tween(begin: _tiltY, end: 0.0).animate(
      CurvedAnimation(parent: _restCtrl, curve: Curves.elasticOut),
    );
    _restCtrl.forward(from: 0);
    _restCtrl.addListener(_applyRest);
  }

  void _applyRest() {
    if (_restX == null || _restY == null) return;
    setState(() {
      _tiltX = _restX!.value;
      _tiltY = _restY!.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cardWidth = mq.size.width * 0.86;
    final cardHeight = cardWidth * 1.4;

    return GestureDetector(
      // 카드 밖 영역 탭 → 닫기
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _entryCtrl,
        builder: (ctx, _) {
          final t = Curves.easeOutCubic.transform(_entryCtrl.value);
          return Container(
            color: Colors.black.withValues(alpha: 0.88 * t),
            child: SafeArea(
              child: Stack(
                children: [
                  // 카드 (Hero 애니메이션 + pan)
                  Center(
                    child: GestureDetector(
                      onTap: () {}, // 카드 자체 탭은 닫기 방지
                      onPanUpdate: (d) => _onPanUpdate(d, Size(cardWidth, cardHeight)),
                      onPanEnd: _onPanEnd,
                      child: Hero(
                        tag: widget.heroTag,
                        child: _buildTiltedCard(cardWidth, cardHeight),
                      ),
                    ),
                  ),
                  // 닫기 X 버튼
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
                        child: const SizedBox(
                          width: 44, height: 44,
                          child: Icon(Icons.close_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ),
                  // 힌트 (첫 진입 시)
                  Positioned(
                    bottom: 32,
                    left: 0, right: 0,
                    child: Opacity(
                      opacity: (1 - _entryCtrl.value).clamp(0.0, 1.0) * 0 + 0.6,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '드래그해서 카드를 기울여보세요',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTiltedCard(double w, double h) {
    // 카드 자체 회전 — perspective + rotateX/Y
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0012) // perspective
      ..rotateY(_tiltX * 0.4)
      ..rotateX(-_tiltY * 0.4);

    // tilt 따라 spot light 위치 (-1~1 정규화 → -0.7~0.7 안쪽)
    final spotX = _tiltX * 0.7;
    final spotY = -_tiltY * 0.7;

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 카드 뒤 그림자 (입체감)
            Positioned(
              top: 16, left: 0, right: 0, bottom: -16,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
              ),
            ),
            // 카드 이미지 — 채도/명도 미세 enhance (카드 본 색감 강조)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColorFiltered(
                colorFilter: _saturationFilter(1.12 + 0.06 * _intensity),
                child: CardImage(
                  imageUrl: widget.imageUrl,
                  cdnFallbackUrl: widget.cdnFallbackUrl,
                  width: w,
                  height: h,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            // Spot light — tilt 위치에 자연스러운 광택 (RadialGradient, 매우 옅음)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(spotX, spotY),
                        radius: 0.6,
                        colors: [
                          Colors.white.withValues(alpha: 0.18 * _intensity),
                          Colors.white.withValues(alpha: 0.06 * _intensity),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.35, 1.0],
                      ),
                      backgroundBlendMode: BlendMode.softLight,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
            // 엣지 하이라이트 (가장자리 반사 — 매우 미세)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10 * _intensity),
                      width: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 채도 강화 매트릭스. 카드 본래 색감을 더 진하게.
  static ColorFilter _saturationFilter(double s) {
    // ITU-R BT.709 luminance coefficients
    const lr = 0.213, lg = 0.715, lb = 0.072;
    final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
    return ColorFilter.matrix(<double>[
      ir + s, ig,     ib,     0, 0,
      ir,     ig + s, ib,     0, 0,
      ir,     ig,     ib + s, 0, 0,
      0,      0,      0,      1, 0,
    ]);
  }

}

/// 카드 열기 helper — 어디서든 호출 가능.
Future<void> openHolographicCard(
  BuildContext context, {
  required String heroTag,
  required String rarity,
  String? imageUrl,
  String? cdnFallbackUrl,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => HolographicCardViewer(
        heroTag: heroTag,
        rarity: rarity,
        imageUrl: imageUrl,
        cdnFallbackUrl: cdnFallbackUrl,
      ),
    ),
  );
}
