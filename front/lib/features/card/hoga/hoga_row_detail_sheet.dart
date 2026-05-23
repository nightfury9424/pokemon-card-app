import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auth_image.dart';
import 'models/hoga_board_model.dart';
import 'models/hoga_listing_model.dart';
import 'services/hoga_api.dart';
import 'utils/hoga_format.dart';

/// 호가 row 클릭 시 등장하는 하단 시트 — 그 가격에 걸린 등록자 리스트.
///
/// 정책 (feedback_hoga_design_invariants.md):
/// - ASK row → 실제 TradePost 리스트. row 탭 시 sheet 닫고 호출자가 `/trades/{tradeId}` 로 push.
///   sheet 내부 context 로 직접 push 하면 deactivated context 리스크가 있어, parent context 콜백 패턴 사용.
/// - BID row → 실제 BuyOrder 리스트. 1차는 disabled + inline "준비 중" 안내. SnackBar 금지.
/// - ASK 인데 tradeId 결손이면 disabled + inline 결함 안내. silent 무동작 금지.
class HogaRowDetailSheet extends StatefulWidget {
  final String cardId;
  final HogaStatus status;
  final HogaGrade? grade;
  final HogaSide side;
  final int price;

  /// ASK row 탭 시 sheet pop 후 호출됨. 호출자가 parent context 로 라우팅한다.
  final void Function(String tradeId)? onOpenTradeDetail;

  /// DraggableScrollableSheet 의 scroll controller. ListView 와 sheet drag 를 연결.
  final ScrollController? scrollController;

  const HogaRowDetailSheet({
    super.key,
    required this.cardId,
    required this.status,
    required this.grade,
    required this.side,
    required this.price,
    this.onOpenTradeDetail,
    this.scrollController,
  });

  /// 편의 호출자 — `showModalBottomSheet`로 띄움.
  static Future<void> show(
    BuildContext context, {
    required String cardId,
    required HogaStatus status,
    required HogaGrade? grade,
    required HogaSide side,
    required int price,
    void Function(String tradeId)? onOpenTradeDetail,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scroll) => HogaRowDetailSheet(
          cardId: cardId,
          status: status,
          grade: grade,
          side: side,
          price: price,
          onOpenTradeDetail: onOpenTradeDetail,
          scrollController: scroll,
        ),
      ),
    );
  }

  @override
  State<HogaRowDetailSheet> createState() => _HogaRowDetailSheetState();
}

class _HogaRowDetailSheetState extends State<HogaRowDetailSheet> {
  late final Future<HogaListings> _future;

  @override
  void initState() {
    super.initState();
    _future = HogaApi.fetchListings(
      widget.cardId,
      widget.price,
      status: widget.status,
      grade: widget.grade,
      side: widget.side,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 색상 정책 (feedback_color_policy.md): 매도=빨강, 매수=파랑.
    final color = widget.side == HogaSide.ask ? AppColors.red : AppColors.blue;
    final sideLabel = widget.side == HogaSide.ask ? '판매 호가' : '매수 호가';
    final statusLabel = widget.grade == null
        ? widget.status.label
        : '${widget.status.label} ${widget.grade!.label}';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // drag handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  sideLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  formatKrw(widget.price),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          // BID 시트는 1차 전체 disabled 상태 — 헤더 색(파랑)이 "매수 가능"으로 오인되지 않게 상단 안내 1줄.
          if (widget.side == HogaSide.bid)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              color: AppColors.blue.withValues(alpha: 0.06),
              child: const Text(
                '매수 호가 상세는 준비 중입니다. 곧 판매 제안/채팅으로 연결돼요.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // 리스트
          Expanded(
            child: FutureBuilder<HogaListings>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '리스트를 불러오지 못했습니다.\n${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                  );
                }
                final data = snap.data!;
                if (data.listings.isEmpty) {
                  return const Center(
                    child: Text(
                      '이 가격에 등록된 호가가 없습니다.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  );
                }
                return ListView.separated(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: data.listings.length,
                  separatorBuilder: (_, _) => const Divider(
                    color: AppColors.dividerSoft,
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                  ),
                  itemBuilder: (_, i) => _ListingTile(
                    listing: data.listings[i],
                    cardId: widget.cardId,
                    side: widget.side,
                    color: color,
                    onOpenTradeDetail: widget.onOpenTradeDetail,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingTile extends StatelessWidget {
  final HogaListing listing;
  final String cardId;
  final HogaSide side;
  final Color color;
  final void Function(String tradeId)? onOpenTradeDetail;

  const _ListingTile({
    required this.listing,
    required this.cardId,
    required this.side,
    required this.color,
    required this.onOpenTradeDetail,
  });

  String _relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 30) return '${diff.inDays}일 전';
    return '${(diff.inDays / 30).floor()}개월 전';
  }

  @override
  Widget build(BuildContext context) {
    final nick = (listing.nickname == null || listing.nickname!.isEmpty)
        ? '익명'
        : listing.nickname!;
    final hasMemo = listing.memo != null && listing.memo!.trim().isNotEmpty;

    final bool isAsk = side == HogaSide.ask;
    final String? tradeId = listing.tradeId;
    final bool clickable = isAsk && tradeId != null && tradeId.isNotEmpty;

    // 정책 (feedback_hoga_design_invariants.md):
    // - BID → 1차 disabled + inline "준비 중" 안내.
    // - ASK 인데 tradeId 결손 → disabled + inline 결함 안내. 백엔드 모니터링 대상.
    final String? helperText = !isAsk
        ? '매수 호가 상세는 준비 중입니다'
        : (clickable ? null : '판매글 정보를 불러올 수 없습니다');

    final Color nameColor = clickable ? AppColors.textPrimary : AppColors.textMuted;
    final Color memoColor = clickable ? AppColors.textSecondary : AppColors.textMuted;

    final tile = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isAsk)
            _AskThumbnail(
              tradeImageUrl: listing.tradeImageUrl,
              cardId: cardId,
              borderColor: clickable ? color : AppColors.divider,
            )
          else
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(
                  nick.characters.first,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nick,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    // ASK status chip — OPEN(판매 중)·RESERVED(예약 중) 둘 다 표시.
                    // raw status 노출 금지. BID 는 표시하지 않음.
                    if (isAsk && listing.tradeStatus != null) ...[
                      const SizedBox(width: 6),
                      Builder(builder: (_) {
                        final isReserved = listing.tradeStatus == 'RESERVED';
                        final chipColor = isReserved
                            ? AppColors.gold
                            : AppColors.green;
                        final chipLabel = isReserved ? '예약 중' : '판매 중';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: chipColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            chipLabel,
                            style: TextStyle(
                              color: chipColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
                if (hasMemo) ...[
                  const SizedBox(height: 2),
                  Text(
                    listing.memo!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: memoColor,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (helperText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    helperText,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  _relative(listing.createdAt),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // trailing — clickable 일 때만 chevron (토스식 "상세 진입 가능" 신호)
          if (clickable)
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 20),
        ],
      ),
    );

    if (!clickable) return tile;

    // Material > InkWell 패턴 — ripple ancestor 보장.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final id = tradeId; // clickable 가드로 non-null 보장.
          Navigator.of(context).pop();
          onOpenTradeDetail?.call(id);
        },
        child: tile,
      ),
    );
  }
}

/// ASK 호가 row 썸네일 — 사용자 업로드 → fallback 카드 기본 이미지.
class _AskThumbnail extends StatelessWidget {
  final String? tradeImageUrl;
  final String cardId;
  final Color borderColor;

  const _AskThumbnail({
    required this.tradeImageUrl,
    required this.cardId,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final base = ApiConstants.baseUrl;
    final url = (tradeImageUrl != null && tradeImageUrl!.isNotEmpty)
        ? (tradeImageUrl!.startsWith('http') ? tradeImageUrl! : '$base$tradeImageUrl')
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: borderColor.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: url != null
            // AuthImage: 호가 row → trade 썸네일 (사용자 업로드)
            ? AuthImage(
                url: url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallbackCardImage(),
              )
            : _fallbackCardImage(),
      ),
    );
  }

  Widget _fallbackCardImage() {
    return Image.network(
      ApiConstants.cardImageUrl(cardId),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.image_not_supported, color: AppColors.textMuted, size: 20),
      ),
    );
  }
}
