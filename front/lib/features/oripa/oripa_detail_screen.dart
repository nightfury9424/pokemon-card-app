import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_list_ui.dart';
import 'oripa_common.dart';
import 'draw/draw_sheets.dart';
import 'data/oripa_mock.dart';
import 'data/oripa_prizes.dart';
import 'data/oripa_session.dart';

/// 오리파 상세 (STEP 2) — 구수 현황 + 대표 상품 + (번호형)상품판.
/// 번호형: [1구 뽑기] → 확인시트 → draw 화면 → 복귀 후 상품판 매칭(스크롤/강조) → 결과시트.
/// 상품 봉인형: 준비 중 mock 유지.
class OripaDetailScreen extends StatefulWidget {
  final String oripaId;
  const OripaDetailScreen({super.key, required this.oripaId});

  @override
  State<OripaDetailScreen> createState() => _OripaDetailScreenState();
}

class _OripaDetailScreenState extends State<OripaDetailScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  final Map<int, GlobalKey> _slotKeys = {};
  int? _focus; // 최근 뽑은 번호(상품판 강조)

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _startDraw(OripaProduct o) async {
    final s = OripaSession.instance;
    if (!s.canDraw(o)) return;
    final ok = await showDrawConfirmSheet(context, o);
    if (ok != true) return;
    final result = s.confirmDraw(o); // 포인트 차감 + 번호 확정(애니 전)
    if (!context.mounted) return;
    // ignore: use_build_context_synchronously — 바로 위 context.mounted 가드됨(analyzer 오탐)
    await context.push('/oripa/draw/${o.oripaId}', extra: result);
    if (!context.mounted) return;
    await _revealOnBoard(o, result);
  }

  Future<void> _revealOnBoard(OripaProduct o, DrawResult result) async {
    setState(() => _focus = result.number);
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    final ctx = _slotKeys[result.number]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx,
          alignment: 0.4,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut);
    }
    await Future.delayed(const Duration(milliseconds: 350));
    if (!context.mounted) return;
    // ignore: use_build_context_synchronously — 바로 위 context.mounted 가드됨(analyzer 오탐)
    final action = await showDrawResultSheet(context, o, result);
    if (!context.mounted) return;
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
                  color: isNumber ? AppColors.blue : AppColors.gold,
                ),
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
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
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
                    showChevron: false,
                  ),
              ]),
              if (isNumber) ...[
                const SizedBox(height: 24),
                const AppSectionLabel('상품판 (번호별 현황)'),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    '뽑힌 번호는 빈자리로 남아요. 노란 번호=명명 상품, 파랑 테두리=내가 뽑은 번호.',
                    style: AppText.muted,
                  ),
                ),
                const SizedBox(height: 12),
                _SlotBoard(oripa: o, session: s, focus: _focus, slotKeys: _slotKeys),
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

/// 번호 오리파 상품판 — 세션 taken 기반. taken=빈자리, chase=노란번호, focus=파랑강조.
class _SlotBoard extends StatelessWidget {
  final OripaProduct oripa;
  final OripaSession session;
  final int? focus;
  final Map<int, GlobalKey> slotKeys;
  const _SlotBoard({
    required this.oripa,
    required this.session,
    required this.focus,
    required this.slotKeys,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (int n = 1; n <= oripa.totalSlots; n++) _slot(n)],
    );
  }

  Widget _slot(int n) {
    final key = slotKeys.putIfAbsent(n, () => GlobalKey());
    final isFocus = focus == n;
    final taken = session.isTaken(oripa, n);
    final chase = OripaDraw.isChase(oripa.oripaId, n);

    Color bg;
    Color fg;
    Border? border;
    String label;
    if (isFocus) {
      bg = AppColors.blue.withValues(alpha: 0.18);
      fg = AppColors.blueLight;
      border = Border.all(color: AppColors.blue, width: 1.5);
      label = '$n';
    } else if (taken) {
      bg = AppColors.dividerSoft;
      fg = AppColors.textMuted;
      label = ''; // 빈자리
    } else if (chase) {
      bg = AppColors.surfaceElevated;
      fg = AppColors.gold;
      label = '$n';
    } else {
      bg = AppColors.surfaceElevated;
      fg = AppColors.textSecondary;
      label = '$n';
    }

    return Container(
      key: key,
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: border,
      ),
      child: Text(label,
          style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: chase || isFocus ? FontWeight.w800 : FontWeight.w600)),
    );
  }
}
