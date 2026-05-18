import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter, TextEditingValue, TextSelection;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/notifiers/asset_notifier.dart';
import '../../core/widgets/card_image.dart';
import '../../core/widgets/holographic_card_viewer.dart';
import '../../core/widgets/rarity_aura.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/price_display_policy.dart';
import 'hoga/hoga_board.dart';
import 'hoga/hoga_row_detail_sheet.dart';

class CardDetailScreen extends StatefulWidget {
  final String cardId;
  final Map<String, dynamic>? cardData;
  final Map<String, dynamic>? myAsset;

  const CardDetailScreen({
    super.key,
    required this.cardId,
    this.cardData,
    this.myAsset,
  });

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // 차트 위에서 시작된 swipe를 TabBarView가 못 받게 — Listener로 PointerDown 위치 detect.
  final GlobalKey _chartKey = GlobalKey();
  bool _swipeLockedByChart = false;

  bool _loading = true;
  Map<String, dynamic>? _cardDetail;
  Map<String, dynamic>? _priceSummary;
  Map<String, dynamic>? _localAsset;
  List<Map<String, dynamic>> _listings = [];
  List<Map<String, dynamic>> _buyOrders = [];  // 4차-Round4-4 Phase 2: 매수 호가
  // HogaBoard chip 기준 카운트 동기화 (2026-05-18). null = 아직 미수신 (헤더는 전체값 fallback).
  int? _hogaAskCount;
  int? _hogaBidCount;
  // HogaBoard 외부 refresh trigger — TradePost/BuyOrder 생성·취소 후 ++.
  int _hogaRefreshKey = 0;
  // 등록 완료 상단 banner — 매수/판매 성공 시 2초 표시. 중복 큐 차단 token.
  // Phase 5: error 분기 추가 — green vs red 색상 결정.
  String? _successBannerText;
  bool _bannerIsError = false;
  int _bannerToken = 0;
  // 내 자산 탭 "대기 중인 주문" — 본인 BuyOrder + 본인 TradePost (이 카드 한정).
  List<Map<String, dynamic>> _myBuyOrders = [];
  List<Map<String, dynamic>> _myTradePosts = [];
  bool _pendingOrdersLoading = false;
  String _selectedMarket = 'KO';
  String _selectedGlobalGrade = 'RAW';

  static const _tutorialKey = 'tutorial_card_detail_seen';
  static const _storage = FlutterSecureStorage();
  OverlayEntry? _coachMarkEntry;

  @override
  void initState() {
    super.initState();
    _localAsset = widget.myAsset != null
        ? Map<String, dynamic>.from(widget.myAsset!)
        : null;
    // 탭 순서 = [시세, 거래, 내 자산]. 기본 진입 = 시세 (index 0).
    // 사용자 흐름: "얼마야 → 사고팔 수 있어 → 내 거/주문은" (feedback_hoga_design_invariants.md 가드레일 8).
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: 0,
    );
    _loadData();
    _maybeShowCoachMark();
  }

  @override
  void dispose() {
    _coachMarkEntry?.remove();
    _coachMarkEntry = null;
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _maybeShowCoachMark() async {
    final seen = await _storage.read(key: _tutorialKey);
    if (seen == '1' || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showCoachMark();
    });
  }

  void _showCoachMark() {
    final overlay = Overlay.of(context);
    _coachMarkEntry = OverlayEntry(builder: (_) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissCoachMark,
              child: Container(color: Colors.black.withValues(alpha: 0.78)),
            ),
          ),
          // 화면 중앙 살짝 아래에 말풍선
          Positioned(
            left: 20,
            right: 20,
            top: MediaQuery.of(context).size.height * 0.35,
            child: _CardDetailCoachBubble(onClose: _dismissCoachMark),
          ),
        ],
      );
    });
    overlay.insert(_coachMarkEntry!);
  }

  void _dismissCoachMark() {
    _coachMarkEntry?.remove();
    _coachMarkEntry = null;
    _storage.write(key: _tutorialKey, value: '1');
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiClient.get('${ApiConstants.cards}/${widget.cardId}'),
        ApiClient.get('${ApiConstants.prices}/${widget.cardId}/price-summary'),
        ApiClient.get(
          '/api/trades',
          params: {'cardId': widget.cardId, 'page': 0, 'size': 20},
        ),
        ApiClient.get('/api/buy-orders/cards/${widget.cardId}'),
      ]);
      if (!mounted) return;
      setState(() {
        _cardDetail = results[0]['data'] as Map<String, dynamic>?;
        _priceSummary = results[1]['data'] as Map<String, dynamic>?;
        final tradesData = results[2]['data'];
        if (tradesData is Map) {
          _listings = List<Map<String, dynamic>>.from(
            tradesData['content'] ?? [],
          );
          // 매도 호가창 표준: 가격 오름차순 (가장 저렴한 매도 위)
          _listings.sort((a, b) {
            final pa = (a['price'] as num?)?.toInt() ?? 1 << 30;
            final pb = (b['price'] as num?)?.toInt() ?? 1 << 30;
            return pa.compareTo(pb);
          });
        }
        _buyOrders = List<Map<String, dynamic>>.from(results[3]['data'] ?? []);
        _loading = false;
      });
      final assetId = _localAsset?['assetId'] as String?;
      if (assetId != null) {
        try {
          final assetRes = await ApiClient.get('/api/assets/$assetId');
          if (mounted && assetRes['data'] is Map) {
            setState(
              () => _localAsset = Map<String, dynamic>.from(
                assetRes['data'] as Map,
              ),
            );
          }
        } catch (_) {}
      } else {
        // 검색/거래탭/홀로그래픽 등에서 myAsset 없이 진입한 경우, 사용자 자산 목록에서 cardId 매칭으로 찾음.
        await _lookupOwnedAsset();
      }
      // 내 자산 탭 "대기 중인 주문" — 본인 BuyOrder + 본인 TradePost (이 카드 한정).
      // 자산 보유 무관 — BuyOrder 는 자산 없어도 가능 (가드레일 9).
      _loadMyPendingOrders();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 본인 BuyOrder OPEN + 본인 TradePost OPEN 을 이 카드 한정으로 fetch.
  /// Phase 1: 백엔드 sellerId+cardId+status 동시 필터로 정정. TradePost 도 status=OPEN 명시.
  Future<void> _loadMyPendingOrders() async {
    if (!mounted) return;
    setState(() => _pendingOrdersLoading = true);
    debugPrint('[Pending] start fetch — cardId=${widget.cardId}');
    try {
      // 본인 BuyOrder (이 카드 + OPEN).
      List<Map<String, dynamic>> buyOrders = [];
      try {
        final res = await ApiClient.get(
          '/api/buy-orders/me',
          params: {'status': 'OPEN', 'cardId': widget.cardId},
        );
        if (res['data'] is List) {
          buyOrders = List<Map<String, dynamic>>.from(
              (res['data'] as List).cast<Map>().map((m) => Map<String, dynamic>.from(m)));
        }
        debugPrint('[Pending] BuyOrder fetched — count=${buyOrders.length} '
            'cardIds=${buyOrders.map((b) => b['cardId']).toList()}');
      } catch (e) {
        debugPrint('[Pending] BuyOrder me fetch error: $e');
      }

      // 본인 TradePost (이 카드 + OPEN, sellerId + cardId + status 동시 필터).
      List<Map<String, dynamic>> tradePosts = [];
      try {
        final meRes = await ApiClient.get('/api/users/me');
        final myUserId = (meRes['data'] as Map?)?['userId'] as String?;
        debugPrint('[Pending] me userId=$myUserId');
        if (myUserId != null) {
          final res = await ApiClient.get(
            '/api/trades',
            params: {
              'cardId': widget.cardId,
              'sellerId': myUserId,
              'status': 'OPEN',
              'size': '20',
            },
          );
          // Page 응답 — content 배열에서 가져옴.
          final dataMap = res['data'];
          final content = dataMap is Map ? dataMap['content'] : null;
          if (content is List) {
            tradePosts = List<Map<String, dynamic>>.from(
                content.cast<Map>().map((m) => Map<String, dynamic>.from(m)));
            // 안전망: 혹시 백엔드가 잘못 반환해도 cardId + status=OPEN 클라이언트 재필터.
            tradePosts = tradePosts
                .where((t) => t['status'] == 'OPEN' && t['cardId'] == widget.cardId)
                .toList();
          }
          debugPrint('[Pending] TradePost fetched — content count=${(content is List) ? content.length : -1} '
              'after-filter count=${tradePosts.length}');
        }
      } catch (e) {
        debugPrint('[Pending] TradePost me fetch error: $e');
      }

      if (mounted) {
        setState(() {
          _myBuyOrders = buyOrders;
          _myTradePosts = tradePosts;
          _pendingOrdersLoading = false;
        });
        debugPrint('[Pending] state set — buyOrders=${buyOrders.length} tradePosts=${tradePosts.length}');
      }
    } catch (e) {
      debugPrint('[Pending] _loadMyPendingOrders error: $e');
      if (mounted) setState(() => _pendingOrdersLoading = false);
    }
  }

  /// 등록/수정/취소 mutation 후 통합 refresh — 사용자 정책: 즉시 화면 반영.
  /// _loadData() + _loadMyPendingOrders() + _hogaRefreshKey++ 한 번에.
  Future<void> _refreshAfterOrderMutation() async {
    if (!mounted) return;
    await _loadData();
    await _loadMyPendingOrders();
    if (mounted) setState(() => _hogaRefreshKey++);
  }

  /// 매수 호가 가격 수정 sheet — 기존 등록 sheet 와 같은 구조 (가격 + tick + 콤마).
  Future<void> _showBuyOrderEditSheet(Map<String, dynamic> order) async {
    final buyOrderId = order['buyOrderId'] as String?;
    if (buyOrderId == null) return;
    final currentPrice = (order['bidPrice'] as num?)?.toInt() ?? 0;
    final priceCtrl = TextEditingController(
      text: currentPrice > 0 ? _formatThousands(currentPrice) : '',
    );
    String? submitError;
    bool submitting = false; // Phase 5: 수정 중 중복 클릭 방지.
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('매수 호가 가격 수정',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  const Text('새 매수 가격',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ThousandsCommaFormatter()],
                    onChanged: (_) => setSheet(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      suffixText: '원',
                      suffixStyle: const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.blue),
                      ),
                    ),
                  ),
                  if (submitError != null) ...[
                    const SizedBox(height: 10),
                    Text(submitError!,
                        style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 20),
                  Builder(builder: (_) {
                    final priceVal = int.tryParse(priceCtrl.text.replaceAll(',', '').trim());
                    final canSubmit = priceVal != null && priceVal > 0 && priceVal != currentPrice && !submitting;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.red,
                          disabledBackgroundColor: AppColors.red.withValues(alpha: 0.35),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: canSubmit
                            ? () async {
                                setSheet(() {
                                  submitting = true;
                                  submitError = null;
                                });
                                try {
                                  await ApiClient.patch(
                                    '/api/buy-orders/$buyOrderId/price',
                                    data: {'bidPrice': priceVal},
                                  );
                                  if (sheetCtx.mounted) Navigator.pop(sheetCtx, true);
                                } catch (e) {
                                  debugPrint('BuyOrder edit error: $e');
                                  if (sheetCtx.mounted) {
                                    setSheet(() {
                                      submitting = false;
                                      submitError = '수정에 실패했어요. 잠시 후 다시 시도해주세요.';
                                    });
                                  }
                                }
                              }
                            : null,
                        child: submitting
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('수정 중...',
                                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                                ],
                              )
                            : const Text('수정',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      }),
    );
    if (result == true && mounted) {
      await _refreshAfterOrderMutation();
      _showSuccessBanner('매수 호가가 수정되었습니다');
    }
  }

  /// 매수 호가 취소 — AlertDialog 확인 후 DELETE.
  Future<void> _confirmCancelBuyOrder(Map<String, dynamic> order) async {
    final buyOrderId = order['buyOrderId'] as String?;
    if (buyOrderId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('매수 호가를 취소할까요?', style: TextStyle(color: Colors.white)),
        content: const Text('이 가격의 매수 호가가 취소돼요.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('취소하기', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.delete('/api/buy-orders/$buyOrderId');
      if (!mounted) return;
      await _refreshAfterOrderMutation();
      _showSuccessBanner('매수 호가가 취소되었습니다');
    } catch (e) {
      debugPrint('BuyOrder delete error: $e');
      _showFailureBanner('취소에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  /// 판매글 가격/메모 수정 sheet. 사진은 read-only 프리뷰만 (교체/삭제는 추후 phase).
  Future<void> _showTradePostEditSheet(Map<String, dynamic> trade) async {
    final tradeId = trade['tradeId'] as String?;
    if (tradeId == null) return;
    final currentPrice = (trade['price'] as num?)?.toInt() ?? 0;
    final currentDesc = trade['description'] as String? ?? '';
    final currentTitle = trade['title'] as String? ?? '';
    // 이미지 URL 추출 — imageUrls (신규) 우선, 없으면 imageUrl comma-sep 파싱 (구버전 호환, Codex [9]).
    final List<String> imageUrls = () {
      final raw = trade['imageUrls'];
      if (raw is List) {
        return raw.whereType<String>().where((s) => s.isNotEmpty).toList();
      }
      final single = trade['imageUrl'];
      if (single is String && single.isNotEmpty) {
        return single.split(',').where((s) => s.isNotEmpty).toList();
      }
      return <String>[];
    }();
    final priceCtrl = TextEditingController(
      text: currentPrice > 0 ? _formatThousands(currentPrice) : '',
    );
    final memoCtrl = TextEditingController(text: currentDesc);
    String? submitError;
    bool submitting = false; // Phase 5: 수정 중 중복 클릭 방지.
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('판매글 수정',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  // 사진 프리뷰 — read-only. 교체/삭제는 추후 phase (사용자 정책).
                  if (imageUrls.isNotEmpty) ...[
                    const Text('등록된 사진',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: imageUrls.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final raw = imageUrls[i];
                          final url = raw.startsWith('http')
                              ? raw
                              : '${ApiConstants.baseUrl}$raw';
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                border: Border.all(color: AppColors.divider),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.image_not_supported,
                                      color: AppColors.textMuted, size: 20),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('판매 가격',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ThousandsCommaFormatter()],
                    onChanged: (_) => setSheet(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      suffixText: '원',
                      suffixStyle: const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('메모 (선택)',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: memoCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.blue),
                      ),
                    ),
                  ),
                  if (submitError != null) ...[
                    const SizedBox(height: 10),
                    Text(submitError!,
                        style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 20),
                  Builder(builder: (_) {
                    final priceVal = int.tryParse(priceCtrl.text.replaceAll(',', '').trim());
                    final canSubmit = priceVal != null && priceVal > 0 && !submitting;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          disabledBackgroundColor: AppColors.blue.withValues(alpha: 0.35),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: canSubmit
                            ? () async {
                                setSheet(() {
                                  submitting = true;
                                  submitError = null;
                                });
                                try {
                                  // PUT 전체 body — title/description 보존 (백엔드 partial 미지원).
                                  await ApiClient.put('/api/trades/$tradeId', {
                                    'data': {
                                      'title': currentTitle,
                                      'description': memoCtrl.text.trim().isNotEmpty
                                          ? memoCtrl.text.trim()
                                          : currentDesc,
                                      'price': priceVal,
                                    },
                                  });
                                  if (sheetCtx.mounted) Navigator.pop(sheetCtx, true);
                                } catch (e) {
                                  debugPrint('TradePost edit error: $e');
                                  if (sheetCtx.mounted) {
                                    setSheet(() {
                                      submitting = false;
                                      submitError = '수정에 실패했어요. 잠시 후 다시 시도해주세요.';
                                    });
                                  }
                                }
                              }
                            : null,
                        child: submitting
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('수정 중...',
                                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                                ],
                              )
                            : const Text('수정',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      }),
    );
    if (result == true && mounted) {
      await _refreshAfterOrderMutation();
      _showSuccessBanner('판매글이 수정되었습니다');
    }
  }

  /// 판매글 취소 — AlertDialog 확인 후 DELETE.
  Future<void> _confirmCancelTradePost(Map<String, dynamic> trade) async {
    final tradeId = trade['tradeId'] as String?;
    if (tradeId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('판매글을 취소할까요?', style: TextStyle(color: Colors.white)),
        content: const Text('이 판매글이 호가창에서 사라져요.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('취소하기', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.delete('/api/trades/$tradeId');
      if (!mounted) return;
      await _refreshAfterOrderMutation();
      _showSuccessBanner('판매글이 취소되었습니다');
    } catch (e) {
      debugPrint('TradePost delete error: $e');
      _showFailureBanner('취소에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  /// 사용자 자산 list에서 widget.cardId와 매칭되는 자산을 찾아 _localAsset에 세팅.
  Future<void> _lookupOwnedAsset() async {
    try {
      final meRes = await ApiClient.get('/api/users/me');
      final userId = (meRes['data'] as Map?)?['userId'] as String?;
      if (userId == null || !mounted) return;
      final res = await ApiClient.get(
        '/api/assets',
        params: {'userId': userId},
      );
      final list = (res['data'] as List?) ?? [];
      final owned = list.cast<Map>().firstWhere(
            (a) => a['cardId'] == widget.cardId,
            orElse: () => const {},
          );
      if (owned.isNotEmpty && mounted) {
        setState(() => _localAsset = Map<String, dynamic>.from(owned));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final assetCard = _localAsset?['card'] is Map
        ? Map<String, dynamic>.from(_localAsset!['card'] as Map)
        : null;
    final data = _cardDetail ?? widget.cardData ?? assetCard;
    final name = data?['name'] ?? '';
    final rarity = data?['rarityCode'] ?? '';
    final number = data?['collectionNumber'] ?? '';
    final productName = data?['productName'] as String?;
    final seriesName = data?['seriesName'] as String?;
    final productType = data?['productType'] as String?;
    final imageUrl = resolveCardImageUrl(data);

    // 카드 hero 동적 sizing — 양옆 여백 거의 없이 + 노치 위 여백 + 카드 비율 100:140 유지
    final mq = MediaQuery.of(context);
    final cardWidth = mq.size.width * 0.85;
    final cardHeight = cardWidth * 1.4;
    final heroTopPadding = mq.padding.top + 12;
    final heroBottomReserve = 130; // 카드 정보(70) + TabBar(52) + 여유(8)
    final heroExpandedHeight = heroTopPadding + cardHeight + heroBottomReserve;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // CardDetailScreen 전체 하단 sticky CTA — 모든 탭/자산 보유 무관 항상 표시
      // (feedback_hoga_design_invariants.md 가드레일 2).
      bottomNavigationBar: _buildBottomCta(
        cardName: name,
        rarity: rarity,
        imageUrl: imageUrl,
        cdnImageUrl: resolveCdnImageUrl(data),
      ),
      body: Stack(
        children: [
          _buildNestedScrollBody(data, name, rarity, number, productName,
              seriesName, productType, imageUrl, cardWidth, cardHeight,
              heroTopPadding, heroExpandedHeight),
          // 등록 완료 상단 banner (Codex 권장: SafeArea top + Stack + AnimatedPositioned + green 2초).
          if (_successBannerText != null)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: AnimatedSlide(
                  offset: Offset.zero,
                  duration: const Duration(milliseconds: 220),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _bannerIsError ? AppColors.red : AppColors.green,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _bannerIsError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_rounded,
                            color: Colors.white, size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _successBannerText!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 기존 body NestedScrollView 부분을 helper 로 분리 (Stack wrap 위해).
  Widget _buildNestedScrollBody(
    Map<String, dynamic>? data,
    String name,
    String rarity,
    String number,
    String? productName,
    String? seriesName,
    String? productType,
    String? imageUrl,
    double cardWidth,
    double cardHeight,
    double heroTopPadding,
    double heroExpandedHeight,
  ) {
    return NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
            sliver: SliverAppBar(
              backgroundColor: AppColors.bg,
              foregroundColor: Colors.white,
              expandedHeight: heroExpandedHeight,
              pinned: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              actions: [
                if (_localAsset != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white38),
                    onPressed: () => _confirmDeleteAsset(),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: _buildCardHeroFull(
                  data,
                  name,
                  rarity,
                  number,
                  productName,
                  seriesName,
                  productType,
                  imageUrl,
                  cardWidth: cardWidth,
                  cardHeight: cardHeight,
                  topPadding: heroTopPadding,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  color: AppColors.bg,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.divider, width: 0.6),
                    ),
                    child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '시세'),
                  Tab(text: '거래'),
                  Tab(text: '내 자산'),
                ],
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
                indicator: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(3),
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                dividerColor: Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: Listener(
          // PointerDown 위치가 차트 영역이면 TabBarView swipe lock — fl_chart의 점 툴팁은 그대로.
          // 차트 외 빈 공간 swipe는 정상 동작.
          onPointerDown: (e) {
            final ctx = _chartKey.currentContext;
            final box = ctx?.findRenderObject() as RenderBox?;
            if (box == null || !box.attached) {
              if (_swipeLockedByChart) setState(() => _swipeLockedByChart = false);
              return;
            }
            final rect = box.localToGlobal(Offset.zero) & box.size;
            final inside = rect.contains(e.position);
            if (inside != _swipeLockedByChart) {
              setState(() => _swipeLockedByChart = inside);
            }
          },
          child: TabBarView(
          controller: _tabController,
          physics: _swipeLockedByChart
              ? const NeverScrollableScrollPhysics()
              : null,
          children: [
            // 탭 순서 = [시세, 거래, 내 자산] (가드레일 8).
            Builder(builder: (ctx) => _buildMarketTab(ctx)),
            Builder(builder: (ctx) => _buildTradeTab(ctx, name, rarity)),
            Builder(
              builder: (ctx) => _buildAssetTab(
                ctx, data, name, rarity, imageUrl, productName, seriesName, productType,
              ),
            ),
          ],
          ),
        ),
      );
  }

  // ─────────────────────────────────────────────
  // 풀와이드 카드 히어로 (SliverAppBar flexibleSpace)
  // ─────────────────────────────────────────────

  Widget _buildCardHeroFull(
    Map<String, dynamic>? data,
    String name,
    String rarity,
    String number,
    String? productName,
    String? seriesName,
    String? productType,
    String? imageUrl, {
    required double cardWidth,
    required double cardHeight,
    required double topPadding,
  }) {
    final bgUrl = imageUrl ?? resolveCdnImageUrl(data);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 블러 배경
        if (bgUrl != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Image.network(
              bgUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => Container(color: AppColors.bg),
            ),
          )
        else
          Container(color: AppColors.surfaceCard),

        // 어두운 오버레이
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC0D1117), Color(0x990D1117)],
            ),
          ),
        ),

        // 카드 이미지 (중앙, Hero 애니메이션) — 탭 시 풀스크린 홀로그램 뷰어
        Positioned(
          top: topPadding,
          left: 0,
          right: 0,
          bottom: 130,
          child: Center(
            child: RarityAura(
              rarity: rarity,
              radius: 110,
              intensity: 0.9,
              child: GestureDetector(
                onTap: () => openHolographicCard(
                  context,
                  heroTag: 'card-${widget.cardId}',
                  rarity: rarity,
                  imageUrl: imageUrl,
                  cdnFallbackUrl: resolveCdnImageUrl(data),
                ),
                child: Hero(
                  tag: 'card-${widget.cardId}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.55),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: CardImage(
                      imageUrl: imageUrl,
                      cdnFallbackUrl: resolveCdnImageUrl(data),
                      width: cardWidth,
                      height: cardHeight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 하단: 카드명 + 배지 + 번호 + 세트 정보
        // bottom 48 — SliverAppBar.bottom(TabBar) 높이만큼 띄워서 탭 라벨과 겹치지 않게
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.bg.withOpacity(0.95),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (rarity.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _buildBadge(rarity),
                    ],
                    if (number.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        number,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                if (productName != null || seriesName != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    [if (productName != null) productName, if (seriesName != null) seriesName]
                        .join(' · '),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // Tab 0: 내 자산
  // ─────────────────────────────────────────────

  Widget _buildAssetTab(
    BuildContext ctx,
    Map<String, dynamic>? data,
    String name,
    String rarity,
    String? imageUrl,
    String? productName,
    String? seriesName,
    String? productType,
  ) {
    final handle = NestedScrollView.sliverOverlapAbsorberHandleFor(ctx);
    if (_localAsset == null) {
      return CustomScrollView(
        slivers: [
          SliverOverlapInjector(handle: handle),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const Icon(Icons.inbox_outlined, color: Colors.white24, size: 52),
                  const SizedBox(height: 14),
                  const Text(
                    '아직 보유하지 않은 카드입니다',
                    style: TextStyle(color: Colors.white38, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _ctaButton(
                    label: '스캔으로 추가',
                    icon: Icons.camera_alt_outlined,
                    onTap: () async {
                      // Phase 6: 스캔 후 자동 복귀 + 통합 refresh + green banner.
                      // ScannerScreen 은 expectedCardId 검증 + 등록 후 pop(true) 패턴 이미 구현됨.
                      final result = await context.push<bool>(
                        '/scanner?expectedCardId=${widget.cardId}',
                      );
                      if (result == true && mounted) {
                        await _refreshAfterOrderMutation();
                        _showSuccessBanner('자산이 등록되었습니다');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '이 카드와 동일한 카드만 등록됩니다',
                    style: TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          // 자산 미보유 분기에도 "대기 중인 주문" 영역 — BuyOrder 는 자산 없어도 가능 (가드레일 9).
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _buildPendingOrdersSection(),
            ),
          ),
          // 하단 sticky CTA 가림 방지 padding.
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      );
    }

    final asset = _localAsset!;
    final purchasePrice = (asset['purchasePrice'] as num?)?.toInt();
    // PnL은 asset의 displayPrice(language·grade 반영) 기준으로 — KO mid는 JP/EN/GRADED 자산에서 왜곡됨.
    final displayPrice = (asset['displayPrice'] as num?)?.toInt();
    final priceBasis = asset['displayPriceBasis'] as String?;
    final isRawFallback = priceBasis == 'RAW_FALLBACK';

    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(handle: handle),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, _localAsset != null ? 100 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // PSA10 시세 없어서 RAW로 폴백된 경우 안내
                if (isRawFallback) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'PSA 10 시세 데이터가 아직 없어 RAW 시세 기준으로 표시됩니다.',
                            style: TextStyle(
                              color: Colors.amber.shade200,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // P&L 섹션
                if (purchasePrice != null && purchasePrice > 0 && displayPrice != null)
                  _buildPnLSection(purchasePrice, displayPrice),
                if (purchasePrice != null && purchasePrice > 0 && displayPrice != null)
                  const SizedBox(height: 16),

                // 등급/자산 정보
                _buildAssetGradeSection(),
                const SizedBox(height: 16),

                // 세트 정보
                if (productName != null || seriesName != null)
                  _buildProductInfoCard(data, productName, seriesName, productType),
                if (productName != null || seriesName != null)
                  const SizedBox(height: 16),

                // 보유 메타
                _buildAssetMetaCard(asset),
                const SizedBox(height: 16),
                // 토스 패턴 "대기 중인 주문" — 본인 BuyOrder + 본인 TradePost (가드레일 9).
                _buildPendingOrdersSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ctaButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.blue, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// KO 추정가 전일 대비 변동률 (charts.ko.line의 마지막 두 점 기준).
  /// PriceDisplayPolicy(2026-05-16)로 저가 카드 % 숨김/Stage B 전체 숨김/Stage C 변동 적음 자동 처리.
  /// 가디안 V "0원 (-18.8%)" 버그 방지 — diff/percent 통합 산출.
  PriceChangeDisplay? _koDailyChange() {
    final ko = _priceSummary?['charts']?['ko'] as Map?;
    final line = ko?['line'];
    if (line is! List || line.length < 2) return null;
    final last = line[line.length - 1];
    final prev = line[line.length - 2];
    if (last is! Map || prev is! Map) return null;
    final lastPrice = (last['price'] as num?)?.toInt();
    final prevPrice = (prev['price'] as num?)?.toInt();
    return PriceDisplayPolicy.buildChangeDisplay(
      lastPrice: lastPrice,
      prevPrice: prevPrice,
      showZero: false, // 카드 상세는 diff==0 숨김 (정보성 X)
    );
  }

  Widget _buildPnLSection(int purchasePrice, int marketPrice) {
    final diff = marketPrice - purchasePrice;
    final pct = purchasePrice > 0 ? (diff * 100.0 / purchasePrice) : 0.0;
    final isGain = diff >= 0;
    // 색상 정책 (feedback_color_policy.md): 한국 주식 관습. 양=빨강, 음=파랑.
    final color = isGain ? AppColors.red : AppColors.blue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '내 보유 현황',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _pnlCell('구매가', _formatPrice(purchasePrice), Colors.white54),
              ),
              Container(width: 1, height: 36, color: AppColors.divider),
              Expanded(
                child: _pnlCell('현재가', _formatPrice(marketPrice), Colors.white),
              ),
              Container(width: 1, height: 36, color: AppColors.divider),
              Expanded(
                child: _pnlCell(
                  '손익',
                  '${isGain ? '+' : '-'}${_formatPrice(diff.abs())}',
                  color,
                ),
              ),
            ],
          ),
          if (diff != 0) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${isGain ? '+' : '-'}${pct.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pnlCell(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductInfoCard(
    Map<String, dynamic>? data,
    String? productName,
    String? seriesName,
    String? productType,
  ) {
    return GestureDetector(
      onTap: () async {
        final productId = _cardDetail?['productId'] as String?;
        if (productId != null) {
          await context.push(
            '/product/$productId',
            extra: {
              'productName': productName,
              'seriesName': seriesName,
            },
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, color: Colors.white38, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (productName != null)
                    Text(
                      productName,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  if (seriesName != null)
                    Text(
                      seriesName,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (productType != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _productTypeLabel(productType),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  /// 토스 패턴 "대기 중인 주문" — 본인 BuyOrder OPEN + 본인 TradePost OPEN (이 카드 한정).
  /// 가드레일 9: 자산 보유 무관 표시. 수정/취소 wiring 은 Step 2-C.
  Widget _buildPendingOrdersSection() {
    final hasAny = _myBuyOrders.isNotEmpty || _myTradePosts.isNotEmpty;
    if (_pendingOrdersLoading && !hasAny) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!hasAny) {
      // 빈 상태도 사용자가 "내 주문 영역이 있다"는 사실 인지하게 약하게 표시.
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.6),
        ),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, color: AppColors.textMuted, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '대기 중인 주문이 없어요',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              const Text(
                '대기 중인 주문',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              // Phase 5: re-fetch 진행 표시 — 기존 데이터 있는 상태에서도 작은 spinner.
              if (_pendingOrdersLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        // 매도 (내 판매글) — 정책: 매도 = red
        for (final tp in _myTradePosts)
          _pendingOrderRow(
            isBuy: false,
            badge: '판매중',
            badgeColor: AppColors.green,
            label: '판매',
            cardStatus: tp['cardStatus'] as String?,
            gradingCompany: tp['gradingCompany'] as String?,
            gradeValue: tp['gradeValue'] as String?,
            price: (tp['price'] as num?)?.toInt() ?? 0,
            qty: 1,
            onEdit: () => _showTradePostEditSheet(tp),
            onCancel: () => _confirmCancelTradePost(tp),
          ),
        // 매수 (내 주문) — 정책: 매수 = blue
        for (final bo in _myBuyOrders)
          _pendingOrderRow(
            isBuy: true,
            badge: '대기',
            badgeColor: AppColors.blue,
            label: '구매',
            cardStatus: bo['cardStatus'] as String?,
            gradingCompany: bo['gradingCompany'] as String?,
            gradeValue: bo['gradeValue'] as String?,
            price: (bo['bidPrice'] as num?)?.toInt() ?? 0,
            qty: (bo['qty'] as num?)?.toInt() ?? 1,
            onEdit: () => _showBuyOrderEditSheet(bo),
            onCancel: () => _confirmCancelBuyOrder(bo),
          ),
      ],
    );
  }

  Widget _pendingOrderRow({
    required bool isBuy,
    required String badge,
    required Color badgeColor,
    required String label,
    required String? cardStatus,
    required String? gradingCompany,
    required String? gradeValue,
    required int price,
    required int qty,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
  }) {
    final actionColor = isBuy ? AppColors.blue : AppColors.red;
    final stateLabel = cardStatus == 'GRADED' &&
            gradingCompany != null &&
            gradeValue != null
        ? '$gradingCompany $gradeValue'
        : (cardStatus ?? 'RAW');
    final priceStr = price.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 0.6),
      ),
      child: Row(
        children: [
          // [대기/판매중] badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 구매/판매 N장 + 상태/가격
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$label $qty장',
                      style: TextStyle(
                        color: actionColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        stateLabel,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$priceStr원',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // [수정] ghost — Phase 2 wiring 완료.
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            child: const Text('수정'),
          ),
          // [취소] danger.
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.red,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetMetaCard(Map<String, dynamic> asset) {
    final cardStatus = asset['cardStatus'] as String? ?? 'RAW';
    final addedAt = asset['createdAt'] as String?;
    final quantity = (asset['quantity'] as num?)?.toInt() ?? 1;
    final certNumber = asset['certNumber'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metaRow('카드 상태', cardStatus == 'GRADED' ? '등급 카드' : 'RAW'),
          if (quantity > 1) ...[
            const SizedBox(height: 8),
            _metaRow('보유 수량', '$quantity장'),
          ],
          if (certNumber != null && certNumber.isNotEmpty) ...[
            const SizedBox(height: 8),
            _metaRow('인증번호', certNumber),
          ],
          if (addedAt != null) ...[
            const SizedBox(height: 8),
            _metaRow('추가일', addedAt.length > 10 ? addedAt.substring(0, 10) : addedAt),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // Tab 1: 시세
  // ─────────────────────────────────────────────

  Widget _buildMarketTab(BuildContext ctx) {
    // 시세 탭 = 시세 차트만. 매도 호가 리스트는 거래 탭의 HogaBoard로 이전 (2026-05-18).
    // _buildOrderBookSection() 함수는 아직 남아있지만 호출 제거됨.
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: _buildPriceSection(),
          ),
        ),
        // 하단 sticky CTA 가림 방지 padding.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // Tab 2: 거래
  // ─────────────────────────────────────────────

  Widget _buildTradeTab(BuildContext ctx, String cardName, String rarity) {
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
        ),
        // 4차-Round4-4 Phase 4: 호가창 강화 — 현재가 + 양방향 묶음
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _buildOrderBookHeader(),
          ),
        ),
        // 호가창 (Phase G 임시 통합 — KREAM/StockX hybrid)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: HogaBoard(
              cardId: widget.cardId,
              refreshKey: _hogaRefreshKey,
              onCountsChanged: (ask, bid) {
                if (mounted &&
                    (_hogaAskCount != ask || _hogaBidCount != bid)) {
                  setState(() {
                    _hogaAskCount = ask;
                    _hogaBidCount = bid;
                  });
                }
              },
              onRowTap: (price, side, status, grade) {
                HogaRowDetailSheet.show(
                  context,
                  cardId: widget.cardId,
                  status: status,
                  grade: grade,
                  side: side,
                  price: price,
                  // Phase E2: ASK row 탭 시 sheet 닫힌 뒤 parent context 로 push.
                  onOpenTradeDetail: (tradeId) {
                    if (!context.mounted) return;
                    context.push('/trades/$tradeId');
                  },
                );
              },
              // 등록 CTA 는 CardDetailScreen 하단 sticky footer [판매하기][구매하기] 담당
              // — HogaBoard 내부 버튼 두지 않음 (feedback_hoga_design_invariants.md).
            ),
          ),
        ),
        // 기존 "이 카드 판매 중" / "이 카드 매수 호가" 박스는 HogaBoard로 대체됨 (2026-05-18).
        // _buildListingsSection / _buildBuyOrdersSection 호출 제거.
        // 하단 sticky CTA 가림 방지 padding.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  /// 호가창 상단 — 현재가 + 매도/매수 카운트 한 줄
  Widget _buildOrderBookHeader() {
    final koMid = (_priceSummary?['ko']?['mid'] as num?)?.toInt();
    // 호가창 chip 기준 카운트 우선. HogaBoard에서 setState로 받음.
    final sellCount = _hogaAskCount ?? _listings.length;
    final buyCount = _hogaBidCount ?? _buyOrders.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('대표 시세', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                const SizedBox(height: 4),
                Text(
                  koMid != null ? _formatPrice(koMid) : '시세 없음',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: AppColors.divider),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 색상 정책 (feedback_color_policy.md): 매도=빨강, 매수=파랑.
              Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '매도 $sellCount',
                    style: const TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '매수 $buyCount',
                    style: const TextStyle(color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 매수 호가 등록 bottom sheet
  Future<void> _showBuyOrderRegisterSheet() async {
    String cardStatus = 'RAW';
    String? gradingCompany;
    String? gradeValue;
    // 예상가치를 가격 초기값으로 (KO mid 대표 시세) — tick 단위로 floor.
    // ex) 26,210,940 + tick 100,000 → 26,200,000
    final midPrice = (_priceSummary?['ko']?['mid'] as num?)?.toInt();
    final initialPrice = midPrice != null ? _floorToTick(midPrice) : null;
    // 컨트롤러 dispose 는 sheet dismiss animation 중 TextField rebuild 와 충돌 (TextEditingController used after disposed).
    // 정석은 별도 StatefulWidget 으로 분리해 State.dispose 활용 — 다음 polish 에서 처리. 지금은 dispose 생략 (1회성 시트라 누수 무시).
    final priceCtrl = TextEditingController(
      // 입력 표시는 콤마 포맷 — 자릿수 가독성 위해. 파싱 시 콤마 제거.
      text: initialPrice != null ? _formatThousands(initialPrice) : '',
    );
    final memoCtrl = TextEditingController();
    String? submitError; // 등록 실패 시 sheet 내부 inline 표시.
    bool submitting = false; // Phase 5: 등록 중 중복 클릭 방지 + "등록 중..." 표시.
    // 카드 거래 수량은 1 고정 — 수량 UI 제거.

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '이 가격에 사고 싶어요',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '매수 호가를 등록하면 판매자가 보고 채팅으로 연락해요.',
                    style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  // 상태 선택
                  const Text('카드 상태', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _statusChip('RAW (등급 무관)', 'RAW', cardStatus, () {
                        setSheet(() { cardStatus = 'RAW'; gradingCompany = null; gradeValue = null; });
                      }),
                      const SizedBox(width: 8),
                      _statusChip('등급 카드', 'GRADED', cardStatus, () {
                        setSheet(() { cardStatus = 'GRADED'; });
                      }),
                    ],
                  ),
                  if (cardStatus == 'GRADED') ...[
                    const SizedBox(height: 16),
                    const Text('감정사', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: ['PSA', 'BRG'].map((c) {
                        final sel = gradingCompany == c;
                        return GestureDetector(
                          onTap: () => setSheet(() => gradingCompany = c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.blue : AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sel ? AppColors.blue : AppColors.divider),
                            ),
                            child: Text(c, style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text('등급', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['10', '9', '8'].map((v) {
                        final sel = gradeValue == v;
                        return GestureDetector(
                          onTap: () => setSheet(() => gradeValue = v),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.gold.withValues(alpha: 0.2) : AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sel ? AppColors.gold : AppColors.divider),
                            ),
                            child: Text(v, style: TextStyle(color: sel ? AppColors.gold : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('매수 희망 가격', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ThousandsCommaFormatter()],
                    onChanged: (_) => setSheet(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: '예: 26,200,000',
                      hintStyle: const TextStyle(color: Colors.white24),
                      suffixText: '원',
                      suffixStyle: const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: memoCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: '특이사항 (선택) — 예: 한정판만 OK',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.surface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.blue),
                      ),
                    ),
                  ),
                  if (submitError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.red, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              submitError!,
                              style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Builder(builder: (_) {
                    // 검증 (Codex 정책: SnackBar 대신 버튼 비활성). 파싱은 콤마 제거 후.
                    final priceVal = int.tryParse(priceCtrl.text.replaceAll(',', '').trim());
                    final priceOk = priceVal != null && priceVal > 0;
                    final gradeOk = cardStatus == 'RAW' ||
                        (gradingCompany != null && gradeValue != null);
                    final canSubmit = priceOk && gradeOk && !submitting;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          // 색상 정책 (feedback_color_policy.md): 매수 액션 = 빨강 (토스 컨벤션).
                          backgroundColor: AppColors.red,
                          disabledBackgroundColor: AppColors.red.withValues(alpha: 0.35),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: canSubmit
                            ? () async {
                                setSheet(() {
                                  submitting = true;
                                  submitError = null;
                                });
                                try {
                                  await ApiClient.post('/api/buy-orders', {
                                    'data': {
                                      'cardId': widget.cardId,
                                      'bidPrice': priceVal,
                                      'qty': 1,
                                      'cardStatus': cardStatus,
                                      if (gradingCompany != null) 'gradingCompany': gradingCompany,
                                      if (gradeValue != null) 'gradeValue': gradeValue,
                                      if (memoCtrl.text.trim().isNotEmpty) 'memo': memoCtrl.text.trim(),
                                    },
                                  });
                                  if (sheetCtx.mounted) Navigator.pop(sheetCtx, true);
                                } catch (e) {
                                  // 등록 실패 — sheet 내부 inline error 표시 (SnackBar 금지).
                                  debugPrint('BuyOrder create error: $e');
                                  if (sheetCtx.mounted) {
                                    setSheet(() {
                                      submitting = false;
                                      submitError = '등록에 실패했어요. 잠시 후 다시 시도해주세요.';
                                    });
                                  }
                                }
                              }
                            : null,
                        child: submitting
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('등록 중...',
                                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                                ],
                              )
                            : const Text('매수 호가 등록',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      }),
    );
    // priceCtrl/memoCtrl dispose — sheet dismiss animation 중 rebuild 충돌로 크래시.
    // StatefulWidget 분리 polish 전까지 생략 (1회성 시트, 누수 무시 가능).
    if (result == true && mounted) {
      await _refreshAfterOrderMutation();
      _showSuccessBanner('매수 호가가 등록되었습니다');
    }
  }

  Widget _statusChip(String label, String value, String current, VoidCallback onTap) {
    final sel = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? AppColors.blue.withValues(alpha: 0.18) : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppColors.blue : AppColors.divider),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: sel ? AppColors.blue : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
      ),
    );
  }

  // 매수 호가 섹션 (4차-Round4-4 Phase 2)
  Widget _buildBuyOrdersSection(String cardName, String rarity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '이 카드 매수 호가',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_buyOrders.length}',
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _showBuyOrderRegisterSheet(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 13),
                    SizedBox(width: 4),
                    Text(
                      '매수 호가',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_buyOrders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '아직 매수 호가가 없습니다.\n첫 번째 매수자가 되어보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
              ),
            ),
          )
        else
          ..._buyOrders.take(5).map((order) {
            final price = order['bidPrice'] as num?;
            final buyerNickname = order['buyerNickname'] as String? ?? '익명';
            final cardStatus = order['cardStatus'] as String? ?? 'RAW';
            final gradingCompany = order['gradingCompany'] as String?;
            final gradeValue = order['gradeValue'] as String?;
            final qty = order['qty'] as num? ?? 1;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.green.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                cardStatus == 'GRADED' && gradingCompany != null && gradeValue != null
                                    ? '$gradingCompany $gradeValue'
                                    : 'RAW',
                                style: const TextStyle(
                                  color: AppColors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              buyerNickname,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (qty > 1) ...[
                              const SizedBox(width: 4),
                              Text(
                                '× $qty',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          price != null ? '${AppColors.formatPrice(price.toInt())}에 사고 싶음' : '-',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chat_bubble_outline_rounded,
                      color: AppColors.green.withValues(alpha: 0.7), size: 18),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // 한국 예상 가치 + 해외 시세 차트
  // ─────────────────────────────────────────────

  Widget _buildPriceSection() {
    final assetCard = _localAsset?['card'] is Map
        ? Map<String, dynamic>.from(_localAsset!['card'] as Map)
        : null;
    final data = _cardDetail ?? widget.cardData ?? assetCard;
    final isPromo = data?['isPromoExclusive'] == true;
    final hasJpRef = _hasScrydexRef(data?['jpScrydexRef']);
    final hasEnRef = _hasScrydexRef(data?['enScrydexRef']);
    final koBasis = _priceSummary?['ko']?['basis'] as String?;
    final koLabel = isPromo
        ? (koBasis == 'RAW_FROM_PSA10'
              ? 'JP 추정 RAW (PSA10 × 비율)'
              : (koBasis == 'SCRYDEX_JP_PSA10'
                    ? 'JP 시세 (PSA10 기준)'
                    : (hasJpRef ? 'JP 시세' : (hasEnRef ? 'EN 시세' : '시세'))))
        : 'KO 예상 가치';

    final ko = _priceSummary?['ko'] as Map<String, dynamic>?;
    final charts = _priceSummary?['charts'] as Map<String, dynamic>?;
    final enPsa = _priceSummary?['enPsa'] as Map<String, dynamic>?;
    final jpPsa = _priceSummary?['jpPsa'] as Map<String, dynamic>?;

    final koMid = (ko?['mid'] as num?)?.toInt();
    final koLow = (ko?['low'] as num?)?.toInt();
    final koHigh = (ko?['high'] as num?)?.toInt();

    final enChart = charts?['en'] as Map<String, dynamic>?;
    final jpChart = charts?['jp'] as Map<String, dynamic>?;
    final enLine = enChart?['line'] as List?;
    final jpLine = jpChart?['line'] as List?;
    final activePsa = _selectedMarket == 'JP' ? jpPsa : enPsa;
    final double? lastRaw = _selectedMarket == 'JP'
        ? (jpLine?.isNotEmpty == true
              ? (jpLine!.last['price'] as num?)?.toDouble()
              : null)
        : (enLine?.isNotEmpty == true
              ? (enLine!.last['price'] as num?)?.toDouble()
              : null);

    final double? activePsa10 = (activePsa?['psa10Usd'] as num?)?.toDouble();
    final double? activePsa9 = (activePsa?['psa9Usd'] as num?)?.toDouble();

    final hasData = koMid != null || lastRaw != null || activePsa10 != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '시세 차트',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              _buildMarketTabs(),
            ],
          ),
          const SizedBox(height: 12),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      color: Colors.white30,
                      strokeWidth: 2,
                    ),
                    SizedBox(height: 10),
                    Text(
                      '시세 불러오는 중...',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else if (!hasData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '시세 데이터 없음',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
            )
          else ...[
            if (_selectedMarket == 'KO') ...[
              if (koMid != null && koLow != null && koHigh != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _formatPrice(koLow),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '~',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      _formatPrice(koHigh),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Builder(builder: (_) {
                  // 소유자: 등록 시점(구매가) 대비. 비소유자: 전일 대비.
                  final purchase = (_localAsset?['purchasePrice'] as num?)?.toInt();
                  final isOwner = purchase != null && purchase > 0;
                  String? changeLabel;
                  Color? changeColor;
                  if (isOwner) {
                    // PriceDisplayPolicy (2026-05-16): 등록 시점 대비도 동일 정책 — 가디안 V "0원 -X.X%" 버그 방지
                    final display = PriceDisplayPolicy.buildChangeDisplay(
                      lastPrice: koMid,
                      prevPrice: purchase,
                      prefix: '등록 시점 대비',
                      showZero: false,
                    );
                    if (display != null) {
                      changeLabel = display.label;
                      changeColor = switch (display.color) {
                        PriceChangeColor.positive => AppColors.red,
                        PriceChangeColor.negative => AppColors.blue,
                        PriceChangeColor.neutral => Colors.white54,
                      };
                    }
                  } else {
                    // PriceDisplayPolicy (2026-05-16): 저가 카드 % 숨김/Stage B 전체 숨김/Stage C 변동 적음
                    final display = _koDailyChange();
                    if (display != null) {
                      changeLabel = display.label;
                      changeColor = switch (display.color) {
                        PriceChangeColor.positive => AppColors.red,
                        PriceChangeColor.negative => AppColors.blue,
                        PriceChangeColor.neutral => Colors.white54,
                      };
                    }
                  }
                  return Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$koLabel  ·  대표가 ${_formatPrice(koMid)}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (changeLabel != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            changeLabel,
                            style: TextStyle(
                              color: changeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  );
                }),
                const SizedBox(height: 4),
                _buildKoBasisRow(ko),
                const SizedBox(height: 12),
                _buildKoPriceChips(charts, koLow, koHigh, koBasis),
              ],
            ] else ...[
              Row(
                children: [
                  if (lastRaw != null) ...[
                    _buildPriceChip(
                      'RAW NM',
                      lastRaw,
                      '\$',
                      const Color(0xFF2196F3),
                      selected: _selectedGlobalGrade == 'RAW',
                      onTap: () => setState(() => _selectedGlobalGrade = 'RAW'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (activePsa10 != null)
                    _buildPriceChip(
                      'PSA 10',
                      activePsa10,
                      '\$',
                      const Color(0xFFFFD700),
                      selected: _selectedGlobalGrade == 'PSA10',
                      onTap: () =>
                          setState(() => _selectedGlobalGrade = 'PSA10'),
                    ),
                  if (activePsa9 != null) ...[
                    const SizedBox(width: 8),
                    _buildPriceChip(
                      'PSA 9',
                      activePsa9,
                      '\$',
                      const Color(0xFF90CAF9),
                      selected: _selectedGlobalGrade == 'PSA9',
                      onTap: () =>
                          setState(() => _selectedGlobalGrade = 'PSA9'),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),

            _buildMarketChart(charts),
            const SizedBox(height: 10),
            _buildMarketLegend(),
          ],
        ],
      ),
    );
  }

  // KO 예상가 근거 표시: EN 기준 × 환율 × 계수
  Widget _buildKoBasisRow(Map<String, dynamic>? ko) {
    final enUsd = (ko?['enUsd'] as num?)?.toDouble();
    final exchangeRate = (ko?['exchangeRate'] as num?)?.toDouble();
    final coefficient = (ko?['coefficient'] as num?)?.toDouble();

    if (enUsd == null && exchangeRate == null) return const SizedBox.shrink();

    final parts = <String>[];
    if (enUsd != null) parts.add('EN \$${enUsd.toStringAsFixed(2)}');
    if (exchangeRate != null) parts.add('환율 ${exchangeRate.toStringAsFixed(0)}');
    if (coefficient != null) parts.add('계수 ${coefficient.toStringAsFixed(2)}');

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' × '),
      style: const TextStyle(color: Colors.white24, fontSize: 10),
    );
  }

  Widget _buildKoPriceChip(
    String label,
    int? low,
    int? high, {
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final color = label == 'RAW'
        ? const Color(0xFF4CAF50)
        : label == 'PSA 10'
        ? const Color(0xFFFFD700)
        : const Color(0xFF90CAF9);
    final hasPrice = low != null && high != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(selected ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withOpacity(selected ? 0.75 : 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            if (hasPrice)
              Text(
                '${_formatCompactWon(low)} ~ ${_formatCompactWon(high)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              )
            else ...[
              const Text(
                '???',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                '거래 데이터 없음',
                style: TextStyle(color: Colors.white24, fontSize: 9),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 메타몽 같은 NO_EN/NO_JP 카드: KO 차트에 psa10/9Line 있으면 EN/JP와 동일 3-카드 Row.
  // 데이터 부족하면 기존 범위 카드 (RAW low~high) 사용.
  // koBasis가 'SCRYDEX_JP_PSA10'이면 일본 PSA10 fallback이라 'RAW' 라벨 X — 칩을 PSA 10으로 표기.
  Widget _buildKoPriceChips(
      Map<String, dynamic>? charts, int? koLow, int? koHigh, String? koBasis) {
    final koChart = charts?['ko'] as Map<String, dynamic>?;
    final koPsa10Line = koChart?['psa10Line'] as List?;
    final koPsa9Line = koChart?['psa9Line'] as List?;
    final hasKoGraded =
        (koPsa10Line?.length ?? 0) >= 2 || (koPsa9Line?.length ?? 0) >= 2;
    if (!hasKoGraded) {
      // 한국 graded 데이터 없을 때: koBasis 따라 라벨 분기.
      // - RAW_FROM_PSA10 / SCRYDEX_JP_PSA10 / PSA10 → PSA10 기반 → "RAW 추정" 라벨
      //   (RAW_FROM_PSA10은 ratio 환산 완료, PSA10은 fallback)
      // - 그 외 → RAW
      final isPsaBased = koBasis == 'RAW_FROM_PSA10'
          || koBasis == 'SCRYDEX_JP_PSA10'
          || koBasis == 'PSA10';
      final label = koBasis == 'RAW_FROM_PSA10' ? 'RAW 추정'
          : isPsaBased ? 'PSA 10' : 'RAW';
      return _buildKoPriceChip(label, koLow, koHigh, selected: true, onTap: null);
    }
    final koLineList = koChart?['line'] as List?;
    final lastRawKrw = (koLineList != null && koLineList.isNotEmpty)
        ? (koLineList.last['price'] as num?)?.toDouble()
        : null;
    final psa10Krw = (koPsa10Line != null && koPsa10Line.isNotEmpty)
        ? (koPsa10Line.last['price'] as num?)?.toDouble()
        : null;
    final psa9Krw = (koPsa9Line != null && koPsa9Line.isNotEmpty)
        ? (koPsa9Line.last['price'] as num?)?.toDouble()
        : null;
    return Row(
      children: [
        if (lastRawKrw != null) ...[
          _buildPriceChip('RAW', lastRawKrw, '', AppColors.green,
              selected: _selectedGlobalGrade == 'RAW',
              onTap: () => setState(() => _selectedGlobalGrade = 'RAW'),
              isWon: true),
          const SizedBox(width: 8),
        ],
        if (psa10Krw != null)
          _buildPriceChip('PSA 10', psa10Krw, '', const Color(0xFFFFD700),
              selected: _selectedGlobalGrade == 'PSA10',
              onTap: () => setState(() => _selectedGlobalGrade = 'PSA10'),
              isWon: true),
        if (psa9Krw != null) ...[
          const SizedBox(width: 8),
          _buildPriceChip('PSA 9', psa9Krw, '', const Color(0xFF90CAF9),
              selected: _selectedGlobalGrade == 'PSA9',
              onTap: () => setState(() => _selectedGlobalGrade = 'PSA9'),
              isWon: true),
        ],
      ],
    );
  }

  Widget _buildPriceChip(
    String label,
    double price,
    String prefix,
    Color color, {
    bool selected = false,
    VoidCallback? onTap,
    bool isWon = false,   // KO 모드: 정수 + 콤마 + '원'
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(selected ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withOpacity(selected ? 0.75 : 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              isWon
                  ? _formatCompactWon(price.toInt())   // KO: "21.4만" 같은 만 단위 축약
                  : '$prefix${price.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketTabs() {
    return Row(
      children: ['KO', 'JP', 'EN'].map((market) {
        final selected = _selectedMarket == market;
        return GestureDetector(
          onTap: () {
            String globalGrade = 'RAW';
            if (market != 'KO' && _priceSummary != null) {
              final ck = market == 'JP' ? 'jp' : 'en';
              final cds =
                  (_priceSummary!['charts'] as Map<String, dynamic>?)?[ck]
                      as Map<String, dynamic>?;
              final rawLine = cds?['line'] as List?;
              if (rawLine == null || rawLine.length < 2) {
                final p10 = cds?['psa10Line'] as List?;
                if (p10 != null && p10.length >= 2) {
                  globalGrade = 'PSA10';
                } else {
                  final p9 = cds?['psa9Line'] as List?;
                  if (p9 != null && p9.length >= 2) globalGrade = 'PSA9';
                }
              }
            }
            setState(() {
              _selectedMarket = market;
              _selectedGlobalGrade = globalGrade;
            });
          },
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? AppColors.blue : Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              market,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMarketChart(Map<String, dynamic>? charts) {
    final bool isKrw = _selectedMarket == 'KO';

    final chartKey = isKrw ? 'ko' : (_selectedMarket == 'JP' ? 'jp' : 'en');
    final chartData = charts?[chartKey] as Map<String, dynamic>?;
    final chartType = chartData?['chartType'] as String? ?? 'LINE';
    final chartReason = chartData?['reason'] as String? ?? 'OK';

    if (chartType == 'LINE_WITH_POINTS') {
      return _buildLineWithPointsChart(chartData, chartReason);
    }

    final bool isPoints = chartType == 'POINTS';

    // KO/JP/EN 모두 동일 패턴: psa10Line/psa9Line 있으면 등급 selector 작동, 없으면 line(RAW) 사용.
    // (NO_EN/NO_JP 카드인 메타몽은 backend가 KO에도 KREAM 시계열로 psa10/9Line 채움)
    final List? rawData;
    if (isPoints) {
      rawData = chartData?['points'] as List?;
    } else {
      final rawLine = chartData?['line'] as List?;
      final psa10Line = chartData?['psa10Line'] as List?;
      final psa9Line = chartData?['psa9Line'] as List?;

      List? selected = switch (_selectedGlobalGrade) {
        'PSA10' => psa10Line,
        'PSA9' => psa9Line,
        _ => rawLine,
      };

      if (selected == null || selected.length < 2) {
        String? fallback;
        if (_selectedGlobalGrade != 'PSA10' &&
            psa10Line != null &&
            psa10Line.length >= 2) {
          selected = psa10Line;
          fallback = 'PSA10';
        } else if (_selectedGlobalGrade != 'PSA9' &&
            psa9Line != null &&
            psa9Line.length >= 2) {
          selected = psa9Line;
          fallback = 'PSA9';
        } else if (_selectedGlobalGrade != 'RAW' &&
            rawLine != null &&
            rawLine.length >= 2) {
          selected = rawLine;
          fallback = 'RAW';
        }
        if (fallback != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedGlobalGrade != fallback) {
              setState(() => _selectedGlobalGrade = fallback!);
            }
          });
        }
      }
      rawData = selected;
    }

    if ((rawData == null || rawData.isEmpty) && chartType == 'NONE') {
      return _buildNoUsefulChartBox(chartReason);
    }

    final activeColor = isKrw
        ? const Color(0xFF4CAF50)
        : _selectedGlobalGrade == 'PSA10'
        ? const Color(0xFFFFD700)
        : _selectedGlobalGrade == 'PSA9'
        ? const Color(0xFF90CAF9)
        : (_selectedMarket == 'JP'
              ? const Color(0xFFFFB74D)
              : const Color(0xFF2196F3));

    if (rawData == null || rawData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '데이터 없음',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    final startDate =
        DateTime.tryParse(rawData.first['date'] as String? ?? '') ??
        DateTime.now();
    final spots = rawData
        .map<FlSpot?>((p) {
          final dt = DateTime.tryParse(p['date'] as String? ?? '');
          final price = (p['price'] as num?)?.toDouble();
          if (dt == null || price == null || price <= 0) return null;
          return FlSpot(dt.difference(startDate).inDays.toDouble(), price);
        })
        .whereType<FlSpot>()
        .toList();

    if (spots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '데이터 없음',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    final allY = spots.map((s) => s.y).toList();
    // PriceDisplayPolicy Stage D: KO 차트만 최소 range 1,000원 적용 (저가 V자 차단).
    // JP/EN은 USD 단위라 1,000 minRange가 차트 바닥에 붙는 버그 발생 → 기존 로직 유지.
    final double minY;
    final double maxY;
    if (isKrw) {
      final range = PriceDisplayPolicy.adjustChartRange(
        dataMin: allY.reduce((a, b) => a < b ? a : b),
        dataMax: allY.reduce((a, b) => a > b ? a : b),
        representativePrice: spots.last.y,
      );
      minY = range.minY;
      maxY = range.maxY;
    } else {
      minY = (allY.reduce((a, b) => a < b ? a : b) * 0.88).clamp(0.0, double.infinity);
      maxY = allY.reduce((a, b) => a > b ? a : b) * 1.12;
    }
    final yStep = (maxY - minY) / 2;
    final lastX = spots.last.x.clamp(1.0, double.infinity);
    final xInterval = (lastX / 4).ceilToDouble().clamp(1.0, double.infinity);

    final bar = LineChartBarData(
      spots: spots,
      isCurved: false,
      color: activeColor,
      barWidth: 1.8,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [activeColor.withOpacity(0.22), activeColor.withOpacity(0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );

    if (spots.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '데이터 없음',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    final chartWidget = SizedBox(
      key: _chartKey,
      height: 220,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: lastX,
          clipData: const FlClipData.all(),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A2035),
              tooltipRoundedRadius: 10,
              tooltipBorder: const BorderSide(color: Colors.white12),
              getTooltipItems: (pts) => pts.map((s) {
                final val = isKrw
                    ? _formatPrice(s.y.toInt())
                    : '\$${s.y.toStringAsFixed(2)}';
                return LineTooltipItem(
                  val,
                  TextStyle(
                    color: activeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yStep > 0 ? yStep : null,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Colors.white10, strokeWidth: 0.8),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 62,
                interval: yStep > 0 ? yStep : null,
                getTitlesWidget: (v, m) {
                  if (v == m.min || v == m.max) return const SizedBox.shrink();
                  final label = isKrw
                      ? _formatPrice(v.toInt())
                      : '\$${v.toStringAsFixed(0)}';
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: xInterval,
                getTitlesWidget: (v, m) {
                  if (v == m.min || v == m.max) return const SizedBox.shrink();
                  final dt = startDate.add(Duration(days: v.toInt()));
                  return Text(
                    '${dt.month}/${dt.day}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [bar],
        ),
      ),
    );

    if (chartReason == 'FLAT_DATA') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chartWidget,
          const SizedBox(height: 4),
          const Row(
            children: [
              Icon(Icons.trending_flat, color: Colors.white24, size: 12),
              SizedBox(width: 4),
              Text(
                '30일 변동 미미',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
        ],
      );
    }
    return chartWidget;
  }

  Widget _buildLineWithPointsChart(
    Map<String, dynamic>? chartData,
    String reason,
  ) {
    final lineRaw = chartData?['line'] as List? ?? [];
    final pointsRaw = chartData?['points'] as List? ?? [];

    if (lineRaw.isEmpty && pointsRaw.isEmpty) {
      return _buildNoUsefulChartBox(reason);
    }

    DateTime? startDate;
    for (final p in [...lineRaw, ...pointsRaw]) {
      final dt = DateTime.tryParse((p as Map)['date'] as String? ?? '');
      if (dt != null && (startDate == null || dt.isBefore(startDate))) {
        startDate = dt;
      }
    }
    final effectiveStart = startDate ?? DateTime.now();

    FlSpot? toSpot(Map p) {
      final dt = DateTime.tryParse(p['date'] as String? ?? '');
      final price = (p['price'] as num?)?.toDouble();
      if (dt == null || price == null || price <= 0) return null;
      return FlSpot(dt.difference(effectiveStart).inDays.toDouble(), price);
    }

    final lineSpots = lineRaw
        .map((p) => toSpot(p as Map))
        .whereType<FlSpot>()
        .toList();
    final pointSpots = pointsRaw
        .map((p) => toSpot(p as Map))
        .whereType<FlSpot>()
        .toList();

    if (lineSpots.isEmpty && pointSpots.isEmpty) {
      return _buildNoUsefulChartBox(reason);
    }

    final allSpots = [...lineSpots, ...pointSpots];
    final allY = allSpots.map((s) => s.y).toList();
    // PriceDisplayPolicy Stage D: KO 차트만 적용. JP/EN은 USD 단위라 기존 로직.
    final bool isKoChart = _selectedMarket == 'KO';
    final double minY;
    final double maxY;
    if (isKoChart) {
      final range = PriceDisplayPolicy.adjustChartRange(
        dataMin: allY.reduce((a, b) => a < b ? a : b),
        dataMax: allY.reduce((a, b) => a > b ? a : b),
        representativePrice: allY.last,
      );
      minY = range.minY;
      maxY = range.maxY;
    } else {
      minY = (allY.reduce((a, b) => a < b ? a : b) * 0.88).clamp(0.0, double.infinity);
      maxY = allY.reduce((a, b) => a > b ? a : b) * 1.12;
    }
    final yStep = (maxY - minY) / 2;
    final lastX = allSpots
        .map((s) => s.x)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    final xInterval = (lastX / 4).ceilToDouble().clamp(1.0, double.infinity);

    const lineColor = Color(0xFF4CAF50);
    const pointColor = Color(0xFFFFC107);

    final bars = <LineChartBarData>[
      if (lineSpots.length >= 2)
        LineChartBarData(
          spots: lineSpots,
          isCurved: false,
          color: lineColor,
          barWidth: 1.8,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [lineColor.withOpacity(0.18), lineColor.withOpacity(0.0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
    ];

    if (bars.isEmpty) return _buildNoUsefulChartBox(reason);

    return SizedBox(
      key: _chartKey,
      height: 220,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: lastX,
          clipData: const FlClipData.all(),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A2035),
              tooltipRoundedRadius: 10,
              tooltipBorder: const BorderSide(color: Colors.white12),
              getTooltipItems: (pts) => pts.map((s) {
                final c = s.barIndex == 0 ? lineColor : pointColor;
                return LineTooltipItem(
                  _formatPrice(s.y.toInt()),
                  TextStyle(
                    color: c,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yStep > 0 ? yStep : null,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Colors.white10, strokeWidth: 0.8),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 62,
                interval: yStep > 0 ? yStep : null,
                getTitlesWidget: (v, m) {
                  if (v == m.min || v == m.max) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      _formatPrice(v.toInt()),
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: xInterval,
                getTitlesWidget: (v, m) {
                  if (v == m.min || v == m.max) return const SizedBox.shrink();
                  final dt = effectiveStart.add(Duration(days: v.toInt()));
                  return Text(
                    '${dt.month}/${dt.day}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  );
                },
              ),
            ),
          ),
          lineBarsData: bars,
        ),
      ),
    );
  }

  Widget _buildMarketLegend() {
    if (_selectedMarket != 'KO') return const SizedBox.shrink();
    final charts = _priceSummary?['charts'] as Map<String, dynamic>?;
    final koChart = charts?['ko'] as Map<String, dynamic>?;
    final chartType = koChart?['chartType'] as String? ?? '';
    if (chartType == 'NONE' || chartType.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 2,
          color: const Color(0xFF4CAF50).withOpacity(0.7),
        ),
        const SizedBox(width: 5),
        const Text(
          'KO 예상 흐름',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // 호가 (판매글 기반 매도 호가)
  // ─────────────────────────────────────────────

  Widget _buildOrderBookSection() {
    final sellOrders = _listings.where((t) => t['price'] != null).toList()
      ..sort((a, b) => (a['price'] as num).compareTo(b['price'] as num));

    if (sellOrders.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '매도 호가',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '낮은 가격순 · 판매글 기준',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...sellOrders.take(5).map((t) {
            final price = (t['price'] as num).toInt();
            final tradeId = t['tradeId'] as String? ?? '';
            final cardStatus = t['cardStatus'] as String? ?? '';
            final gradingCompany = t['gradingCompany'] as String?;
            final gradeValue = t['gradeValue'] as String?;
            final label = cardStatus == 'GRADED' && gradingCompany != null
                ? '$gradingCompany ${gradeValue ?? ''}'
                : 'RAW';
            final condition = t['condition'] as String?;
            return GestureDetector(
              onTap: () async {
                final changed = await context.push<bool>('/trades/$tradeId');
                if (changed == true && mounted) _loadData();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (condition != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          condition,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _formatPrice(price),
                      style: const TextStyle(
                        color: Color(0xFFEF5350),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.white24,
                      size: 14,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAsset() async {
    final assetId = _localAsset?['assetId'] as String?;
    if (assetId == null) return;
    if (_localAsset?['isSelling'] == true) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceCard,
            title: const Text('삭제 불가', style: TextStyle(color: Colors.white)),
            content: const Text(
              '판매 등록된 카드입니다.\n먼저 판매를 내린 후 삭제해주세요.',
              style: TextStyle(color: Colors.white54),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  '확인',
                  style: TextStyle(color: AppColors.blue),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('자산 삭제', style: TextStyle(color: Colors.white)),
        content: const Text(
          '이 카드를 자산에서 삭제하시겠습니까?',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ApiClient.delete('/api/assets/$assetId');
        AssetNotifier.instance.notifyChanged();
        if (!mounted) return;
        context.pop(true);
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────
  // 판매 중 목록
  // ─────────────────────────────────────────────

  Widget _buildListingsSection(String cardName, String rarity) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이 카드 판매 중',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_listings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  '판매 중인 카드가 없습니다',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            )
          else
            ..._listings.take(5).map((trade) {
              final tradeId = trade['tradeId'] ?? '';
              final price = trade['price'] as num?;
              final seller = trade['seller'] as Map<String, dynamic>? ?? {};
              final createdAt = (trade['createdAt'] as String? ?? '');
              final cardStatus = trade['cardStatus'] ?? '';
              final gradingCompany = trade['gradingCompany'] as String?;
              final gradeValue = trade['gradeValue'] as String?;

              return GestureDetector(
                onTap: () async {
                  final changed = await context.push<bool>('/trades/$tradeId');
                  if (changed == true && mounted) _loadData();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.blue.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    cardStatus == 'GRADED' &&
                                            gradingCompany != null
                                        ? '$gradingCompany ${gradeValue ?? ''}'
                                        : 'RAW',
                                    style: const TextStyle(
                                      color: AppColors.blue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  seller['nickname'] ?? '',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              createdAt.length > 10
                                  ? createdAt.substring(0, 10)
                                  : createdAt,
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (price != null)
                            Text(
                              _formatPrice(price.toInt()),
                              style: const TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          else
                            const Text(
                              '가격 협의',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white24,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 하단 sticky CTA — [판매하기] [구매하기]
  // 모든 탭/자산 보유 무관 항상 표시 (feedback_hoga_design_invariants.md 가드레일 2).
  // 색상: 판매하기=파랑 / 구매하기=빨강 (토스증권 액션 컨벤션, 호가창 row 색과 반대).
  // ─────────────────────────────────────────────

  /// 등록 완료 상단 banner — 매수/판매 성공 시 호출. 2초 자동 사라짐, 중복 큐 차단.
  /// SnackBar 금지 정책 (feedback_hoga_design_invariants.md 가드레일 11).
  void _showSuccessBanner(String text) {
    if (!mounted) return;
    final token = ++_bannerToken;
    setState(() {
      _successBannerText = text;
      _bannerIsError = false;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      // 다른 banner 가 덮어쓴 경우 무시.
      if (_bannerToken != token) return;
      setState(() => _successBannerText = null);
    });
  }

  /// 실패 banner — DELETE 등 mutation 실패 시 호출. Phase 5: 사용자 피드백 보강.
  void _showFailureBanner(String text) {
    if (!mounted) return;
    final token = ++_bannerToken;
    setState(() {
      _successBannerText = text;
      _bannerIsError = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_bannerToken != token) return;
      setState(() => _successBannerText = null);
    });
  }

  Widget _buildBottomCta({
    required String cardName,
    required String rarity,
    String? imageUrl,
    String? cdnImageUrl,
  }) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceCard,
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => _onSellTap(cardName, rarity, imageUrl, cdnImageUrl),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  child: const Text('판매하기'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _onBuyTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  child: const Text('구매하기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CTA 액션 분기 (탭 index: 시세=0 / 거래=1 / 내자산=2)
  // 정책: feedback_hoga_design_invariants.md
  // ─────────────────────────────────────────────

  Future<void> _onSellTap(
    String cardName,
    String rarity,
    String? imageUrl,
    String? cdnImageUrl,
  ) async {
    final asset = _localAsset ?? widget.myAsset;
    if (asset == null) {
      // 자산 X — 내 자산 탭으로 이동. 빈 상태 UI 가 "스캔으로 추가" 안내.
      if (_tabController.index != 2) {
        _tabController.animateTo(2);
      }
      return;
    }
    final activeTradeId = asset['activeTradeId'] as String?;
    if (activeTradeId != null) {
      // 활성 판매글 — 그 trade 상세 이동.
      final changed = await context.push<bool>('/trades/$activeTradeId');
      if (changed == true && mounted) {
        _loadData();
        setState(() => _hogaRefreshKey++);
      }
      return;
    }
    // RAW + 자체 그레이딩 분석 결과 없음 → 판매 차단 (가드레일 10).
    final cardStatus = asset['cardStatus'] as String?;
    final estimatedGrade = asset['estimatedGrade'];
    if (cardStatus == 'RAW' && estimatedGrade == null) {
      await _showGradingRequiredSheet(asset: asset, cardName: cardName);
      return;
    }
    // 자산 보유 + 비활성 + 판매 가능 — 거래 탭 이동 + 바로 /trades/create push.
    // 판매 상태 확인 sheet 폐기 (사용자 정책 2026-05-18): 카드당 자산 1개, 판매는 등록된 자산 상태 그대로.
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
    final assetId = asset['assetId'] as String?;
    // 예상가치 (KO mid) tick floor 를 기본 가격으로 전달 — 사용자 정책: 가격 협의 폐지, 자동 기본값.
    final midPrice = (_priceSummary?['ko']?['mid'] as num?)?.toInt();
    final defaultPrice = midPrice != null ? _floorToTick(midPrice) : null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final created = await context.push<bool>('/trades/create', extra: {
        'cardId': widget.cardId,
        'cardName': cardName,
        'rarity': rarity,
        'imageUrl': imageUrl,
        'cdnImageUrl': cdnImageUrl,
        'assetId': assetId,
        'cardStatus': asset['cardStatus'],
        'estimatedGrade': asset['estimatedGrade'],
        'gradingCompany': asset['gradingCompany'],
        'gradeValue': asset['gradeValue'],
        'certNumber': asset['certNumber'],
        if (defaultPrice != null) 'defaultPrice': defaultPrice,
      });
      if (created == true && mounted) {
        await _refreshAfterOrderMutation();
        _showSuccessBanner('판매글이 등록되었습니다');
      }
    });
  }

  /// RAW 자산 + 자체 그레이딩 미완료 → 판매 전 분석 안내 sheet.
  /// 가드레일 10: 분석 후 자동 sheet 재진입 X. 사용자 수동 재클릭.
  Future<void> _showGradingRequiredSheet({
    required Map<String, dynamic> asset,
    required String cardName,
  }) async {
    final assetId = asset['assetId'] as String?;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 14),
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                '먼저 카드 상태를 분석해주세요',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'RAW 카드는 앱 자체 상태 분석을 먼저 진행해야 판매할 수 있어요.\n분석을 마치면 다시 판매하기를 눌러주세요.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    if (!mounted) return;
                    // parent context 로 push (sheet context 직접 push 시 deactivated 위험).
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      if (!mounted) return;
                      final graded = await context.push<bool>(
                        '/grading/capture',
                        extra: {
                          'assetId': assetId,
                          'cardId': widget.cardId,
                          'cardName': cardName,
                        },
                      );
                      if (graded == true && mounted) _loadData();
                    });
                  },
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('상태 분석하기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onBuyTap() {
    // 거래 탭 이동 + 매수 호가 등록 sheet 자동 오픈.
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
    // 탭 전환 직후 시트는 mount/컨텍스트 타이밍이 애매 → 프레임 이후 열기 (Codex 권장).
    // refreshKey 증분은 _showBuyOrderRegisterSheet 내부 result == true 분기에서 처리.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showBuyOrderRegisterSheet();
    });
  }

  Widget _buildAssetGradeSection() {
    final asset = _localAsset!;
    final assetId = asset['assetId'] as String?;
    final cardStatus = asset['cardStatus'] as String? ?? 'RAW';
    final estimatedGrade = (asset['estimatedGrade'] as num?)?.toDouble();
    final gradingCompany = asset['gradingCompany'] as String?;
    final gradeValue = asset['gradeValue'] as String?;
    final centeringScore = (asset['centeringScore'] as num?)?.toDouble();
    final cornerScore = (asset['cornerScore'] as num?)?.toDouble();
    final surfaceScore = (asset['surfaceScore'] as num?)?.toDouble();
    final whiteningScore = (asset['whiteningScore'] as num?)?.toDouble();

    if (cardStatus == 'GRADED' &&
        gradingCompany != null &&
        gradeValue != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                gradingCompany,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              gradeValue,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '등급',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (estimatedGrade != null) {
      Color gradeColor = estimatedGrade >= 9.0
          ? AppColors.green
          : estimatedGrade >= 7.0
          ? AppColors.blue
          : AppColors.red;
      return GestureDetector(
        onTap: assetId != null ? () => _showGradingPhotos(assetId) : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.analytics_outlined,
                    color: AppColors.blue,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '앱 분석 등급',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    estimatedGrade.toStringAsFixed(1),
                    style: TextStyle(
                      color: gradeColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    ' / 10',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.textMuted,
                    size: 16,
                  ),
                ],
              ),
              if (centeringScore != null) ...[
                const SizedBox(height: 10),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _gradeChip('센터링', centeringScore),
                    const SizedBox(width: 8),
                    _gradeChip('코너', cornerScore ?? 0),
                    const SizedBox(width: 8),
                    _gradeChip('표면', surfaceScore ?? 0),
                    const SizedBox(width: 8),
                    _gradeChip('화이트닝', whiteningScore ?? 0),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.textMuted, size: 16),
          SizedBox(width: 8),
          Text(
            '아직 등급 분석이 진행되지 않았습니다',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _showGradingPhotos(String assetId) async {
    List<Map<String, dynamic>> images = [];
    try {
      final res = await ApiClient.get('/api/assets/$assetId/images');
      final data = res['data'];
      if (data is List) {
        images = List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}

    if (!mounted) return;

    final front = images.where((i) => i['imageType'] == 'FRONT').firstOrNull;
    final back = images.where((i) => i['imageType'] == 'BACK').firstOrNull;

    if (front == null && back == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장된 사진이 없습니다'),
          backgroundColor: Color(0xFF1E2235),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '등급 분석 사진',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (front != null)
                    Expanded(
                      child: _photoTile('앞면', front['imageUrl'] as String?),
                    ),
                  if (front != null && back != null) const SizedBox(width: 12),
                  if (back != null)
                    Expanded(
                      child: _photoTile('뒷면', back['imageUrl'] as String?),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  '닫기',
                  style: TextStyle(color: AppColors.blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showExistingGradingResult() async {
    final asset = _localAsset;
    if (asset == null) return;

    final estimatedGrade = (asset['estimatedGrade'] as num?)?.toDouble();
    if (estimatedGrade == null) return;

    final centeringScore = (asset['centeringScore'] as num?)?.toDouble();
    final cornerScore = (asset['cornerScore'] as num?)?.toDouble();
    final surfaceScore = (asset['surfaceScore'] as num?)?.toDouble();
    final whiteningScore = (asset['whiteningScore'] as num?)?.toDouble();
    final assetId = asset['assetId'] as String?;
    final assetCard = _localAsset?['card'] is Map
        ? Map<String, dynamic>.from(_localAsset!['card'] as Map)
        : null;
    final data = _cardDetail ?? widget.cardData ?? assetCard;
    final cardName = data?['name'] ?? widget.cardId;

    List<Map<String, dynamic>> images = [];
    if (assetId != null) {
      try {
        final res = await ApiClient.get('/api/assets/$assetId/images');
        final data = res['data'];
        if (data is List) {
          images = List<Map<String, dynamic>>.from(data);
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final front = images.where((i) => i['imageType'] == 'FRONT').firstOrNull;
    final back = images.where((i) => i['imageType'] == 'BACK').firstOrNull;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '등급 분석 결과',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  estimatedGrade.toStringAsFixed(1),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 48,
                  ),
                ),
                const Text(
                  '/ 10',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _scoreTile('센터링', centeringScore),
                    _scoreTile('코너', cornerScore),
                    _scoreTile('표면', surfaceScore),
                    _scoreTile('화이트닝', whiteningScore),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (front != null)
                      Expanded(
                        child: _photoTile('앞면', front['imageUrl'] as String?),
                      ),
                    if (front != null && back != null)
                      const SizedBox(width: 12),
                    if (back != null)
                      Expanded(
                        child: _photoTile('뒷면', back['imageUrl'] as String?),
                      ),
                    if (front == null && back == null)
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            '저장된 사진이 없습니다',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    final graded = await context.push<bool>(
                      '/grading/capture',
                      extra: {
                        'assetId': assetId,
                        'cardId': widget.cardId,
                        'cardName': cardName,
                      },
                    );
                    if (graded == true && mounted) _loadData();
                  },
                  child: const Text('다시 분석하기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoTile(String label, String? url) {
    return Column(
      children: [
        if (url != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              url.startsWith('http') ? url : '${ApiConstants.baseUrl}$url',
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => const SizedBox(
                height: 180,
                child: Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.white24,
                    size: 40,
                  ),
                ),
              ),
            ),
          )
        else
          const SizedBox(
            height: 180,
            child: Center(
              child: Icon(
                Icons.image_not_supported,
                color: Colors.white24,
                size: 40,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _gradeChip(String label, double score) {
    final color = score >= 9.0
        ? AppColors.green
        : score >= 7.0
        ? AppColors.blue
        : AppColors.red;
    return Column(
      children: [
        Text(
          score.toStringAsFixed(1),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
      ],
    );
  }

  Widget _scoreTile(String label, double? score) {
    final value = score?.toStringAsFixed(1) ?? '-';
    final color = score == null
        ? AppColors.textMuted
        : score >= 9.0
        ? AppColors.green
        : score >= 7.0
        ? AppColors.blue
        : AppColors.red;
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Util
  // ─────────────────────────────────────────────

  String _productTypeLabel(String type) {
    switch (type) {
      case 'BOOSTER':
        return '부스터팩';
      case 'DECK':
        return '덱';
      case 'PROMO':
        return '프로모';
      case 'SPECIAL':
        return '특별판';
      default:
        return type;
    }
  }

  Widget _buildBadge(String rarity) {
    final color = _rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        rarity,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _rarityColor(String rarity) {
    switch (rarity) {
      case 'SAR':
      case 'SSR':
        return const Color(0xFFFFD700);
      case 'BWR':
        return const Color(0xFFE8F5E9);
      case 'CSR':
      case 'CHR':
        return const Color(0xFF00BCD4);
      case 'SR':
      case 'UR':
        return const Color(0xFF9C27B0);
      default:
        return Colors.white54;
    }
  }

  Widget _buildNoUsefulChartBox(String reason) {
    final msg = reason == 'FLAT_DATA'
        ? '최근 30일 가격 변동이 거의 없습니다'
        : '차트로 보기엔 거래 데이터가 부족합니다';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, color: Colors.white24, size: 16),
          const SizedBox(width: 6),
          Text(
            msg,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatCompactWon(int price) {
    if (price >= 10000) {
      final man = price ~/ 10000;
      final sub = (price % 10000) ~/ 1000;
      return sub == 0 ? '$man만' : '$man.${sub}만';
    }
    return '${price ~/ 1000}천';
  }

  bool _hasScrydexRef(Object? ref) {
    final value = ref as String?;
    return value != null && value.isNotEmpty && !value.startsWith('NO_');
  }

  String _formatPrice(int price) {
    if (price <= 0) return '0원';
    final rounded = (price / 10).round() * 10;
    final formatter = rounded.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${formatter}원';
  }

  // ─────────────────────────────────────────────
  // 매수 호가 sheet helper — tick 정규화 + 콤마 포맷
  // HogaTickResolver(Java) 포팅 — 가격 구간별 동적 tick.
  // ─────────────────────────────────────────────

  static int _tickFor(int price) {
    if (price < 100000) return 1000;
    if (price < 1000000) return 5000;
    if (price < 10000000) return 10000;
    return 100000;
  }

  static int _floorToTick(int price) {
    final t = _tickFor(price);
    return (price ~/ t) * t;
  }

  static String _formatThousands(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// 카드 상세 첫 진입 시 1회 표시되는 Coach Mark.
/// 3개 탭(내 자산/시세/거래) 의미를 안내.
class _CardDetailCoachBubble extends StatelessWidget {
  final VoidCallback onClose;
  const _CardDetailCoachBubble({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.blue,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.blue.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '카드 한 장의 모든 정보',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _bullet('내 자산', '내가 보유한 이 카드의 수익률·등급 정보'),
            const SizedBox(height: 8),
            _bullet('시세', 'KO/JP/EN 시세 차트와 가격 비교'),
            const SizedBox(height: 8),
            _bullet('거래', '매도(판매) / 매수(구매) 호가창 + 등록'),
            const SizedBox(height: 14),
            const Text(
              '상단 탭을 눌러 전환해 보세요.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '알겠어요',
                    style: TextStyle(
                      color: AppColors.blue,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
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

  Widget _bullet(String label, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label  ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: desc,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 가격 입력칸 콤마 자동 포맷터. ex) 26210940 → 26,210,940.
class _ThousandsCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue updated) {
    if (updated.text.isEmpty) return updated;
    final digits = updated.text.replaceAll(',', '');
    final value = int.tryParse(digits);
    if (value == null) return old;
    final formatted = _CardDetailScreenState._formatThousands(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
