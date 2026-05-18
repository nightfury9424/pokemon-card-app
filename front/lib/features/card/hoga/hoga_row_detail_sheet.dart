import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/card_image.dart';
import 'models/hoga_board_model.dart';
import 'models/hoga_listing_model.dart';
import 'services/hoga_api.dart';
import 'utils/hoga_format.dart';

/// 호가 row 클릭 시 등장하는 하단 시트 — 그 가격에 걸린 등록자 리스트.
///
/// `showModalBottomSheet`로 띄움. 각 row = 판매자/매수자 + 메모 + 채팅 버튼.
class HogaRowDetailSheet extends StatefulWidget {
  final String cardId;
  final HogaStatus status;
  final HogaGrade? grade;
  final HogaSide side;
  final int price;

  const HogaRowDetailSheet({
    super.key,
    required this.cardId,
    required this.status,
    required this.grade,
    required this.side,
    required this.price,
  });

  /// 편의 호출자 — `showModalBottomSheet`로 띄움.
  static Future<void> show(
    BuildContext context, {
    required String cardId,
    required HogaStatus status,
    required HogaGrade? grade,
    required HogaSide side,
    required int price,
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
                  controller: PrimaryScrollController.maybeOf(ctx),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: data.listings.length,
                  separatorBuilder: (_, __) => const Divider(
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

  const _ListingTile({
    required this.listing,
    required this.cardId,
    required this.side,
    required this.color,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ASK: 카드 이미지 썸네일 (사용자 업로드 → fallback 카드 기본 이미지)
          // BID: 프로필 이니셜
          if (isAsk)
            _AskThumbnail(
              tradeImageUrl: listing.tradeImageUrl,
              cardId: cardId,
              borderColor: color,
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
          // 닉네임 + 메모 + 시각
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nick,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hasMemo) ...[
                  const SizedBox(height: 2),
                  Text(
                    listing.memo!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
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
          // 채팅 버튼 — ASK는 판매자 채팅, BID는 매수자 채팅 (둘 다 채팅 흐름)
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                  isAsk
                      ? '$nick 판매자와 채팅 — Phase F에서 ChatService 연결'
                      : '$nick 매수자와 채팅 — Phase F에서 ChatRoom 확장 + 연결',
                ),
                duration: const Duration(seconds: 2),
              ));
            },
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('채팅', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            style: TextButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          ),
        ],
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
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackCardImage(),
              )
            : _fallbackCardImage(),
      ),
    );
  }

  Widget _fallbackCardImage() {
    // 카드 기본 이미지 (운영 정책: resolveCardImageUrl 우선이지만 cardId만으로는 dict 필요).
    // 가장 단순한 fallback: scrydex CDN 또는 local /images/cards/{id}.jpg.
    return Image.network(
      ApiConstants.cardImageUrl(cardId),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.image_not_supported, color: AppColors.textMuted, size: 20),
      ),
    );
  }
}
