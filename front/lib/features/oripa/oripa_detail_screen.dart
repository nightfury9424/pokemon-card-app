import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_list_ui.dart';
import 'oripa_common.dart';
import 'draw/draw_sheets.dart';
import 'data/oripa_mock.dart';
import 'data/oripa_prizes.dart';
import 'data/oripa_session.dart';

/// 오리파 상세 (STEP 2) — 상품판(실제 상품 이미지+번호) + 뽑기 플로우.
/// 번호형: [1구 뽑기] → 확인시트 → draw 화면 → 복귀 후 상품판 47로 스크롤 →
///         47 상품이 판에서 들려 나와 빈자리 전환 → 결과시트.
/// 상품 봉인형: 준비 중 mock 유지.
class OripaDetailScreen extends StatefulWidget {
  final String oripaId;
  const OripaDetailScreen({super.key, required this.oripaId});

  @override
  State<OripaDetailScreen> createState() => _OripaDetailScreenState();
}

class _OripaDetailScreenState extends State<OripaDetailScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollCtrl = ScrollController();
  final Map<int, GlobalKey> _slotKeys = {};
  late final AnimationController _lift; // 47 상품이 판에서 빠지는 물리 이동(0.5s)
  int? _focus;

  @override
  void initState() {
    super.initState();
    _lift = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _lift.dispose();
    super.dispose();
  }

  Future<void> _startDraw(OripaProduct o) async {
    if (!mounted) return;
    final s = OripaSession.instance;
    if (!s.canDraw(o)) return;
    final ok = await showDrawConfirmSheet(context, o);
    if (!mounted || ok != true) return;
    final result = s.confirmDraw(o); // 포인트 차감 + 번호 확정(애니 전)
    if (!mounted) return;
    await context.push('/oripa/draw/${o.oripaId}', extra: result);
    if (!mounted) return;
    await _revealOnBoard(o, result);
  }

  Future<void> _revealOnBoard(OripaProduct o, DrawResult result) async {
    // 1) 스크롤 도착 시점엔 47 상품이 아직 present(빈자리 전환은 lift 뒤)
    _lift.value = 0;
    setState(() => _focus = result.number);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final ctx = _slotKeys[result.number]?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut);
    }
    // 2) "아, 아까 봤던 리자몽" 인지 여유
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    // 3) 47 상품이 판에서 들려 나옴 → 빈자리 (0.5s 절제된 물리 이동)
    await _lift.forward(from: 0);
    if (!mounted) return;
    // 4) 결과시트
    final action = await showDrawResultSheet(context, o, result);
    if (!mounted) return;
    if (action == 'again') _startDraw(o);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OripaSession.instance,
      builder: (context, _) {
        final o = OripaMock.oripaById(widget.oripaId);
        final shop = OripaMock.shopById(o.shopId);
        final s = OripaSession.instance;
        final remaining = s.remaining(o);
        final isNumber = o.type == OripaType.number;
        final canDraw = s.canDraw(o);
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: oripaAppBar('오리파 상세'),
          body: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(children: [
                AppTagChip(
                    label: o.type.label,
                    color: isNumber ? AppColors.blue : AppColors.gold),
                const SizedBox(width: 8),
                Text(shop.shopName, style: AppText.caption),
              ]),
              const SizedBox(height: 12),
              Text(o.title, style: AppText.h1),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$remaining',
                        style: AppText.h1.copyWith(color: AppColors.blueLight)),
                    Text(' / ${o.totalSlots}구 남음', style: AppText.caption),
                    const Spacer(),
                    Text('1구 ${formatPoint(o.pricePerDraw)}', style: AppText.bodyStrong),
                  ]),
                  const SizedBox(height: 12),
                  OripaSlotBar(1 - remaining / o.totalSlots),
                ]),
              ),
              const SizedBox(height: 24),
              const AppSectionLabel('대표 상품'),
              const SizedBox(height: 8),
              AppGroupCard(children: [
                for (final p in o.featuredPrizes)
                  AppMenuRow(
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.gold,
                      label: p,
                      showChevron: false),
              ]),
              if (isNumber) ...[
                const SizedBox(height: 24),
                const AppSectionLabel('상품판'),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    '실제 상품이 번호와 함께 공개돼요. 뽑힌 번호는 빈자리로 남아요.',
                    style: AppText.muted,
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: _lift,
                  builder: (_, _) => _ProductBoard(
                    oripa: o,
                    session: s,
                    focus: _focus,
                    liftValue: _lift.value,
                    slotKeys: _slotKeys,
                  ),
                ),
              ],
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: OripaPrimaryButton(
              label: isNumber
                  ? (canDraw
                      ? '1구 뽑기 · ${formatPoint(o.pricePerDraw)}'
                      : (remaining <= 0 ? '매진' : '포인트가 부족합니다'))
                  : '1구 뽑기 · ${formatPoint(o.pricePerDraw)}',
              color: (isNumber && !canDraw) ? AppColors.surfaceCard : AppColors.blue,
              onTap: isNumber
                  ? (canDraw ? () => _startDraw(o) : null)
                  : () => oripaComingSoon(context, '상품 봉인 오리파는 준비 중입니다'),
            ),
          ),
        );
      },
    );
  }
}

/// 번호 오리파 상품판 — 실제 상품 이미지 + 번호. taken=빈자리.
/// focus 번호는 lift(0→1)만큼 들려 나가고, lift 완료 후 빈자리로 전환.
class _ProductBoard extends StatelessWidget {
  final OripaProduct oripa;
  final OripaSession session;
  final int? focus;
  final double liftValue;
  final Map<int, GlobalKey> slotKeys;
  const _ProductBoard({
    required this.oripa,
    required this.session,
    required this.focus,
    required this.liftValue,
    required this.slotKeys,
  });

  @override
  Widget build(BuildContext context) {
    // 반복 매핑(8종)이라 URL은 8개뿐 → 100셀이어도 이미지 fetch 8회(캐시 공유).
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: oripa.totalSlots,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (context, i) => _cell(i + 1),
    );
  }

  Widget _cell(int n) {
    final key = slotKeys.putIfAbsent(n, () => GlobalKey());
    final isFocus = focus == n;
    // focus는 lift 끝나기 전까지 상품 present(빈자리 전환 지연).
    final removed = session.isTaken(oripa, n) && !(isFocus && liftValue < 1.0);
    final prize = OripaDraw.prizeForNumber(oripa.oripaId, n);

    Widget content = removed ? _empty(n) : _product(n, prize);
    if (isFocus && !removed && liftValue > 0) {
      content = Transform.translate(
        offset: Offset(0, -12 * liftValue),
        child: Transform.scale(
          scale: 1 + 0.05 * liftValue,
          child: Opacity(opacity: 1 - 0.9 * liftValue, child: content),
        ),
      );
    }
    return KeyedSubtree(key: key, child: content);
  }

  Widget _product(int n, OripaPrize prize) {
    return Column(children: [
      Expanded(child: OripaPrizeTile(prize: prize)),
      const SizedBox(height: 3),
      Text('$n',
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _empty(int n) {
    return Column(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.dividerSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Text('획득',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 3),
      Text('$n',
          style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    ]);
  }
}
