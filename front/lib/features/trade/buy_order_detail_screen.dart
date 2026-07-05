import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_list_ui.dart';
import '../../core/widgets/card_image.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/widgets/pressable.dart';
import '../auth/phone_verify_sheet.dart';
import 'report_sheet.dart';

/// 구매글(매수 호가) 상세 — 판매글(trade_detail)과 대칭 풀페이지.
/// 백엔드 단건 조회가 없어 카드별 매수목록(GET /api/buy-orders/cards/{cardId})을
/// 받아 buyOrderId로 필터. 실물 사진이 없어 카탈로그 카드 이미지 사용.
/// - 비본인: 우상단 신고(BUY_ORDER, App Review 1.2, 공용 ReportSheet) + 하단 채팅하기.
/// - 본인: 우상단 ⋮(가격 수정 / 삭제) — 기존 엔드포인트 재사용. (판매글 owner 대칭)
class BuyOrderDetailScreen extends StatefulWidget {
  final String buyOrderId;
  final String cardId;
  const BuyOrderDetailScreen({super.key, required this.buyOrderId, required this.cardId});

  @override
  State<BuyOrderDetailScreen> createState() => _BuyOrderDetailScreenState();
}

class _BuyOrderDetailScreenState extends State<BuyOrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  bool _chatLoading = false;
  bool _modified = false;
  String? _myUserId;

  bool get _isMine => _myUserId != null && _order?['buyerId'] == _myUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await ApiClient.get('/api/users/me').catchError((_) => {'data': {}});
      _myUserId = (me['data'] as Map?)?['userId'] as String?;
      final res = await ApiClient.get('/api/buy-orders/cards/${widget.cardId}');
      final list = (res['data'] as List?) ?? const [];
      Map<String, dynamic>? found;
      for (final o in list) {
        if (o is Map && o['buyOrderId'] == widget.buyOrderId) {
          found = Map<String, dynamic>.from(o);
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _order = found;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatPrice(num? v) {
    if (v == null) return '-';
    final s = v.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf원';
  }

  void _pop() => context.pop(_modified);

  // ── 채팅하기 (from-buy-order) — card_detail BID 경로와 동일. ──
  Future<void> _startChat() async {
    if (_chatLoading) return;
    if (!await PhoneVerifySheet.ensureVerified(context)) return;
    if (!mounted) return;
    setState(() => _chatLoading = true);
    try {
      final res = await ApiClient.post(
        '/api/chat/rooms/from-buy-order', {'buyOrderId': widget.buyOrderId});
      final room = (res['data'] as Map?)?.cast<String, dynamic>();
      if (room == null || !mounted) return;
      await context.push('/chat/${room['chatRoomId']}', extra: room);
    } catch (e) {
      if (mounted) AppErrorToast.show(context, '채팅을 시작하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  // ── 본인: 가격 수정 (PATCH /api/buy-orders/{id}/price) ──
  Future<void> _editPrice() async {
    final current = (_order?['bidPrice'] as num?)?.toInt() ?? 0;
    final ctrl = TextEditingController(text: current > 0 ? current.toString() : '');
    final newPrice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('매수 희망가 수정',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '새 매수 가격 (원)',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            suffixText: '원',
            suffixStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim().replaceAll(',', ''));
              if (v != null && v > 0) Navigator.of(ctx).pop(v);
            },
            child: const Text('수정', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newPrice == null || !mounted) return;
    try {
      final res = await ApiClient.patch(
        '/api/buy-orders/${widget.buyOrderId}/price', data: {'bidPrice': newPrice});
      if (!mounted) return;
      if (res['status'] != 'success') {
        AppErrorToast.show(context, res['message']?.toString() ?? '수정에 실패했어요.');
        return;
      }
      HapticFeedback.lightImpact(); // 가격 수정 성공 촉각 피드백
      setState(() {
        _order!['bidPrice'] = newPrice;
        _modified = true;
      });
      AppSuccessToast.show(context, '매수 희망가를 수정했어요');
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '수정에 실패했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  // ── 본인: 삭제 (DELETE /api/buy-orders/{id}) ──
  Future<void> _delete() async {
    final ok = await AppConfirmDialog.show(
      context,
      title: '구매글 삭제',
      message: '이 매수 호가를 삭제할까요?\n진행 중인 채팅에 영향을 줄 수 있어요.',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      final res = await ApiClient.delete('/api/buy-orders/${widget.buyOrderId}');
      if (!mounted) return;
      if (res['status'] != 'success') {
        AppErrorToast.show(context, res['message']?.toString() ?? '삭제에 실패했어요.');
        return;
      }
      _modified = true;
      _pop();
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '삭제에 실패했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  void _showOwnerMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
            title: const Text('가격 수정', style: TextStyle(color: AppColors.textPrimary)),
            onTap: () { Navigator.of(ctx).pop(); _editPrice(); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.red),
            title: const Text('삭제', style: TextStyle(color: AppColors.red)),
            onTap: () { Navigator.of(ctx).pop(); _delete(); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final rarity = (o?['rarityCode'] as String?) ?? '';
    final cardStatus = (o?['cardStatus'] as String?) ?? 'RAW';
    final cardName = (o?['cardName'] as String?) ?? (o?['cardId'] as String?) ?? '카드';
    final imageUrl = o?['cardImageUrl'] as String?;
    final bid = o?['bidPrice'] as num?;
    final memo = (o?['memo'] as String?)?.trim();
    final buyer = (o?['buyerNickname'] as String?) ?? '구매자';
    final gc = o?['gradingCompany'] as String?;
    final gv = o?['gradeValue'] as String?;
    final statusLabel = cardStatus == 'GRADED' ? '${gc ?? ''} ${gv ?? ''}'.trim() : 'RAW';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        _pop();
      },
      child: Stack(children: [
        Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: AppColors.textPrimary,
            title: const Text('구매글',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary), onPressed: _pop),
            actions: [
              if (!_loading && o != null)
                _isMine
                    ? IconButton(
                        tooltip: '관리',
                        icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                        onPressed: _showOwnerMenu,
                      )
                    : IconButton(
                        tooltip: '신고하기',
                        icon: const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
                        onPressed: () => ReportSheet.show(
                          context,
                          targetType: 'BUY_ORDER',
                          targetId: widget.buyOrderId,
                          targetNoun: '구매자',
                          autoBlock: false, // 백엔드 BUY_ORDER 자동차단 미지원(1.0.1) → 문구 정확화
                        ),
                      ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2))
              : o == null
                  ? const Center(
                      child: Text('이미 종료되었거나 찾을 수 없는 구매글이에요',
                          style: TextStyle(color: AppColors.textMuted)))
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 카드 이미지 (카탈로그) — 판매글 이미지 섹션 자리.
                          Container(
                            width: double.infinity,
                            height: 380,
                            color: AppColors.surface,
                            alignment: Alignment.center,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CardImage(
                                imageUrl: imageUrl,
                                width: 244,
                                height: 340,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 구매자 정보 (판매글과 동일 — 상단)
                                Row(children: [
                                  Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.blue.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.person, color: AppColors.blue, size: 22),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(buyer,
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 14, fontWeight: FontWeight.w600)),
                                ]),
                                const SizedBox(height: 16),
                                const Divider(color: AppColors.divider),
                                const SizedBox(height: 16),
                                // 제목 + 가격 (판매글과 동일)
                                Text(
                                  '$cardName${rarity.isNotEmpty ? ' [$rarity]' : ''} · $statusLabel 매수',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 18, fontWeight: FontWeight.bold, height: 1.3),
                                ),
                                const SizedBox(height: 10),
                                Text(_formatPrice(bid),
                                    style: const TextStyle(
                                        color: AppColors.green, fontSize: 22, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                const Text('매수 희망가',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                const SizedBox(height: 16),
                                Row(children: [
                                  if (rarity.isNotEmpty)
                                    AppTagChip(
                                        label: rarity,
                                        color: AppColors.rarityColor(rarity),
                                        fontSize: 12),
                                  if (rarity.isNotEmpty) const SizedBox(width: 8),
                                  AppTagChip(
                                      label: statusLabel,
                                      color: AppColors.blueLight,
                                      fontSize: 12),
                                ]),
                                const SizedBox(height: 16),
                                _CardLinkRow(
                                  cardName: cardName,
                                  rarity: rarity,
                                  imageUrl: imageUrl,
                                  onTap: () => context.push('/card/${o['cardId']}'),
                                ),
                                if (memo != null && memo.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  const Text('구매자 메모',
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceCard,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(memo,
                                        style: const TextStyle(
                                            color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
                                  ),
                                ],
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
          bottomNavigationBar: (_loading || o == null || _isMine)
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  // Toss restyle: ElevatedButton → Pressable CTA (게이트 식 동일 —
                  // _chatLoading이면 onTap null = Pressable 비활성, scale/haptic 없음).
                  child: Pressable(
                    pressedScale: 0.97,
                    onTap: _chatLoading ? null : _startChat,
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('채팅하기',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        if (_chatLoading)
          const Positioned.fill(
            child: Material(
              color: AppColors.bg,
              child: Center(child: CircularProgressIndicator(color: AppColors.blue)),
            ),
          ),
      ]),
    );
  }

}

class _CardLinkRow extends StatelessWidget {
  final String cardName;
  final String rarity;
  final String? imageUrl;
  final VoidCallback onTap;
  const _CardLinkRow(
      {required this.cardName, required this.rarity, required this.imageUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      pressedScale: 0.98,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CardImage(imageUrl: imageUrl, width: 44, height: 60, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cardName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                if (rarity.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(rarity, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
                const SizedBox(height: 2),
                const Text('카드 시세 보기',
                    style: TextStyle(color: AppColors.blueLight, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
        ]),
      ),
    );
  }
}
