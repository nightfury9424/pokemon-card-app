import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import 'hoga_status_chip_bar.dart';
import 'models/hoga_board_model.dart';
import 'models/hoga_listing_model.dart';
import 'services/hoga_api.dart';
import 'utils/hoga_format.dart';

/// 주문 전 "호가창 먼저 보여주기" 시트 (거래 UX, 2026-06-03).
///
/// - 구매하기(side=ask) → 기존 **판매글(매도 호가)** 낮은가 먼저. 탭 → 그 거래로(구매).
/// - 판매하기(side=bid) → 기존 **구매 희망(매수 호가)** 높은가 먼저. 탭 → 그 buyer와 채팅(판매).
/// - 원하는 게 없으면 footer → 신규 등록(삽니다/판매글).
///
/// 라우팅은 호출자(card_detail)가 수행 — 시트는 action 만 pop (HogaRowDetailSheet 패턴).
///   결과 Map: {'action':'open','id': tradeId|buyOrderId} / {'action':'register'} / null(닫힘)
///
/// 정책(feedback_hoga_design_invariants): read view + 더미 금지 + 본인 호가 disabled.
/// v1: RAW 기준 (PSA/BRG 조건 필터는 후속). 등록 플로우는 자체 조건 선택 보유.
class PreOrderMatchSheet {
  PreOrderMatchSheet._();

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String cardId,
    required String cardName,
    required HogaSide side,
    String language = 'KO',
    String? myUserId,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scroll) => _PreOrderMatchBody(
          cardId: cardId,
          cardName: cardName,
          side: side,
          language: language,
          myUserId: myUserId,
          scrollController: scroll,
        ),
      ),
    );
  }
}

class _PreOrderMatchBody extends StatefulWidget {
  final String cardId;
  final String cardName;
  final HogaSide side;
  final String language;
  final String? myUserId;
  final ScrollController scrollController;

  const _PreOrderMatchBody({
    required this.cardId,
    required this.cardName,
    required this.side,
    required this.language,
    required this.myUserId,
    required this.scrollController,
  });

  @override
  State<_PreOrderMatchBody> createState() => _PreOrderMatchBodyState();
}

class _PreOrderMatchBodyState extends State<_PreOrderMatchBody> {
  late Future<HogaListings> _future;
  HogaStatus _status = HogaStatus.raw;
  HogaGrade? _grade;

  bool get _isBuy => widget.side == HogaSide.ask; // 구매하기 → 매도 호가(asks)

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<HogaListings> _fetch() => HogaApi.fetchTopListings(
        widget.cardId,
        status: _status,
        grade: _grade,
        side: widget.side,
        limit: 10,
        language: widget.language,
      );

  // RAW/PSA/BRG(+등급) 전환 — 그레이딩 카드도 거래이므로 조건별 호가 조회.
  void _onStatusChanged(HogaStatus status, HogaGrade? grade) {
    if (status == _status && grade == _grade) return;
    setState(() {
      _status = status;
      _grade = grade;
      _future = _fetch();
    });
  }

  void _openListing(HogaListing l) {
    final id = _isBuy ? l.tradeId : l.buyOrderId;
    if (id == null || id.isEmpty) return;
    Navigator.of(context).pop({'action': 'open', 'id': id});
  }

  void _register() => Navigator.of(context).pop({'action': 'register'});

  @override
  Widget build(BuildContext context) {
    // 색상: 매도(판매글)=파랑, 매수(희망)=빨강 (feedback_color_policy).
    final color = _isBuy ? AppColors.blue : AppColors.red;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 조건 토글(RAW/PSA/BRG +등급) — 항상 표시, 빈 조건에서도 전환 가능.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: HogaStatusChipBar(
              selectedStatus: _status,
              selectedGrade: _grade,
              onChanged: _onStatusChanged,
            ),
          ),
          Expanded(
            child: FutureBuilder<HogaListings>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final listings =
                    snap.hasData ? snap.data!.listings : const <HogaListing>[];
                if (snap.hasError) return _errorState();
                // 빈 상태: 중복 카운트 헤더(0명…)·divider 없이 빈 상태가 단독으로.
                if (listings.isEmpty) return _emptyState(color);
                return Column(
                  children: [
                    _header(color, listings.length),
                    const Divider(color: AppColors.divider, height: 1),
                    Expanded(child: _list(listings, color)),
                    _footer(color),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(Color color, int count) {
    final title = _isBuy
        ? '이 카드 판매 중 $count건'
        : '$count명이 이 카드를 찾고 있어요';
    final sub = _isBuy
        ? '마음에 드는 판매글을 탭하면 바로 거래할 수 있어요'
        : '구매 희망자를 탭하면 채팅으로 거래를 시작해요';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<HogaListing> listings, Color color) {
    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: listings.length,
      separatorBuilder: (_, _) => const Divider(
        color: AppColors.dividerSoft,
        height: 1,
        indent: 20,
        endIndent: 20,
      ),
      itemBuilder: (_, i) => _tile(listings[i], color),
    );
  }

  Widget _tile(HogaListing l, Color color) {
    final nick = (l.nickname == null || l.nickname!.isEmpty) ? '익명' : l.nickname!;
    final bool isOwn = widget.myUserId != null && widget.myUserId == l.userId;
    final String? id = _isBuy ? l.tradeId : l.buyOrderId;
    final bool clickable = !isOwn && id != null && id.isNotEmpty;

    final String? helper = isOwn
        ? (_isBuy ? '내 판매글입니다' : '본인 구매 호가입니다')
        : (clickable ? null : '정보를 불러올 수 없습니다');

    final reserved = _isBuy && l.tradeStatus == 'RESERVED';
    final nameColor = clickable ? AppColors.textPrimary : AppColors.textMuted;

    final tile = Padding(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
      child: Row(
        children: [
          // 등록자 프로필 사진 (판매/매수 동일). 카드 썸네일 아님 — 카드 상세라 카드는 중복.
          Opacity(
            opacity: isOwn ? 0.6 : 1.0,
            child: UserAvatar(imageUrl: l.profileImageUrl, size: 40),
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
                    if (reserved) ...[
                      const SizedBox(width: 6),
                      _chip('거래 중', AppColors.gold),
                    ] else if (_isBuy && l.tradeStatus == 'OPEN') ...[
                      const SizedBox(width: 6),
                      _chip('판매중', AppColors.green),
                    ],
                  ],
                ),
                if (helper != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    helper,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  _relative(l.createdAt),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatKrw(l.price),
            style: TextStyle(
              color: clickable ? color : AppColors.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          if (clickable)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 20),
            ),
        ],
      ),
    );

    if (!clickable) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: () => _openListing(l), child: tile),
    );
  }

  Widget _chip(String label, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );

  Widget _emptyState(Color color) {
    final msg = _isBuy ? '아직 이 카드의 판매글이 없어요' : '아직 구매 희망자가 없어요';
    final sub = _isBuy
        ? '구매 희망가를 남기면 카드 보유자에게 알림이 가요'
        : '판매글을 등록하면 구매 희망자에게 노출돼요';
    final cta = _isBuy ? '구매 희망가 등록하기' : '판매글 등록하기';
    // 일러스트+카피는 가용 영역 중앙, CTA는 하단 고정 — 죽은 여백/허전함 해소.
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.inbox_rounded,
                        color: color.withValues(alpha: 0.75), size: 30),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    msg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _register,
                // 등록 CTA = 액션 색 (구매희망가=빨강 / 판매글=파랑, 토스식).
                // 위 카운트/가격 액센트(color)는 보이는 호가 종류 기준이라 별개.
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBuy ? AppColors.red : AppColors.blue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  cta,
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer(Color color) {
    final label = _isBuy ? '원하는 가격이 없으면 · 구매 희망가 등록' : '바로 판매글 등록';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _register,
            // 등록 CTA = 액션 색 (구매희망가=빨강 / 판매글=파랑, 토스식).
            style: OutlinedButton.styleFrom(
              foregroundColor: _isBuy ? AppColors.red : AppColors.blue,
              side: BorderSide(
                  color: (_isBuy ? AppColors.red : AppColors.blue)
                      .withValues(alpha: 0.55)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '호가를 불러오지 못했어요',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _register,
                style: OutlinedButton.styleFrom(
                    foregroundColor: _isBuy ? AppColors.red : AppColors.blue),
                child: Text(_isBuy ? '구매 희망가 등록' : '판매글 등록'),
              ),
            ],
          ),
        ),
      );

  String _relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 30) return '${diff.inDays}일 전';
    return '${(diff.inDays / 30).floor()}개월 전';
  }
}
