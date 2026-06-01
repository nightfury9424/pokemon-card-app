import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';

/// 거래중 상대 선택 sheet — 판매자가 "거래중" 상태로 변경할 때 chat 방 list 중 하나 선택.
///
/// 흐름:
/// 1. 호출자가 `await TradePartnerSelectSheet.show(context, tradeId: ...)` 호출
/// 2. sheet 가 `/api/trades/{id}/chat-partners` fetch 후 list 표시
/// 3. row 선택 → `Navigator.pop(context, chatRoomId)` 반환
/// 4. 호출자가 chatRoomId 받아서 `ApiClient.updateTradeStatus(..., chatRoomId: ...)` 호출
///
/// 빈 상태: 채팅 후보 0건 (예: 아직 buyer 가 채팅 시작 안 함, 또는 모두 차단됨)
class TradePartnerSelectSheet {
  static Future<String?> show(BuildContext context, {required String tradeId}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _TradePartnerSelectSheetBody(tradeId: tradeId),
    );
  }
}

class _TradePartnerSelectSheetBody extends StatefulWidget {
  final String tradeId;
  const _TradePartnerSelectSheetBody({required this.tradeId});

  @override
  State<_TradePartnerSelectSheetBody> createState() =>
      _TradePartnerSelectSheetBodyState();
}

class _TradePartnerSelectSheetBodyState
    extends State<_TradePartnerSelectSheetBody> {
  List<Map<String, dynamic>> _partners = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiClient.getChatPartners(widget.tradeId);
      if (!mounted) return;
      setState(() {
        _partners = list
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppErrorToast.show(context, '거래 상대 목록을 불러오지 못했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '거래 상대 선택',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '선택한 상대만 거래중 채팅을 이어갈 수 있어요.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.blue),
                ),
              )
            else if (_partners.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '채팅 중인 상대가 없습니다',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _partners.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: AppColors.divider, height: 1),
                  itemBuilder: (context, i) {
                    final p = _partners[i];
                    final chatRoomId = p['chatRoomId']?.toString();
                    final nickname = p['buyerNickname']?.toString() ?? '알 수 없는 사용자';
                    final lastMessage = p['lastMessage']?.toString() ?? '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.surfaceElevated,
                        child: Icon(Icons.person,
                            color: AppColors.textMuted, size: 18),
                      ),
                      title: Text(
                        nickname,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: lastMessage.isEmpty
                          ? null
                          : Text(
                              lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                      onTap: chatRoomId == null
                          ? null
                          : () => Navigator.of(context).pop(chatRoomId),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
