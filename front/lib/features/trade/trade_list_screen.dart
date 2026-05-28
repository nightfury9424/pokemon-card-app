import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/price_display_policy.dart';
import '../../core/utils/price_label.dart';
import '../../core/widgets/auth_image.dart';
import '../../core/widgets/card_image.dart';
import 'trade_search_screen.dart';

class TradeListScreen extends StatefulWidget {
  final String? filterCardId;
  final String? filterCardName;
  final String? filterSellerId;
  final String? title;

  const TradeListScreen({
    super.key,
    this.filterCardId,
    this.filterCardName,
    this.filterSellerId,
    this.title,
  });

  @override
  State<TradeListScreen> createState() => _TradeListScreenState();
}

class _TradeListScreenState extends State<TradeListScreen> {
  List<Map<String, dynamic>> _trades = [];
  // 4차-Round4-4 Phase 3 (재설계): 거래 탭 메인 = 카드 list (종목 list 패턴)
  List<Map<String, dynamic>> _marketCards = [];
  int _sortTab = 0; // 0=시세 1=인기 2=급상승 3=급하락
  // 시세 탭(_sortTab == 0) 한정 레어도 필터 — null = 전체.
  // ("등급"은 PSA grading 의미로 쓰이므로 카드 레어도 필터에는 '레어도'로 표기.)
  // 다른 탭으로 이동해도 값은 유지 (시세 복귀 시 자동 재적용); chip 자체는 시세에서만 노출.
  String? _selectedRarity;
  bool _loadingMarket = false;
  bool _loading = true;
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// 카드 찜 상태 (cardId → liked). 거래 리스트 row 하트 표시용.
  final Set<String> _likedCardIds = {};

  final _scrollController = ScrollController();

  // title이 명시되면 명시적 진입(내 판매 항목 등) — 메인 거래 카드 list로 폴백 X.
  // 빈 상태면 _buildBody의 empty 화면 ('등록된 판매 카드가 없습니다')으로 표시.
  bool get _isMainTab =>
      widget.filterCardId == null &&
      widget.filterSellerId == null &&
      widget.title == null;

  @override
  void initState() {
    super.initState();
    if (_isMainTab) {
      _loadMarketCards();
    } else {
      _loadTrades();
    }
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadMarketCards() async {
    setState(() => _loadingMarket = true);
    try {
      List<Map<String, dynamic>> result;
      // 탭별 endpoint 분기 — 모두 백엔드가 정렬 보장.
      // 0=시세(가격 desc), 1=인기(관심수 desc), 2=급상승(gain_pct desc), 3=급하락(gain_pct asc)
      if (_sortTab == 1) {
        final list = await ApiClient.getList('/api/cards/market/popular', params: {'size': 50});
        result = list.whereType<Map>().map((c) => Map<String, dynamic>.from(c)).toList();
      } else if (_sortTab == 2) {
        final list = await ApiClient.getList('/api/cards/market/top-gainers', params: {'size': 50});
        result = list.whereType<Map>().map((c) => Map<String, dynamic>.from(c)).toList();
      } else if (_sortTab == 3) {
        final list = await ApiClient.getList('/api/cards/market/top-losers', params: {'size': 50});
        result = list.whereType<Map>().map((c) => Map<String, dynamic>.from(c)).toList();
      } else {
        // _sortTab == 0 (시세): 가격순 paginated + 레어도 필터 (단일 선택)
        // _selectedRarity == null 이면 전체 rarity (현행 default 그대로 유지).
        final rarities = _selectedRarity ??
            'SSR,SAR,CSR,SR,UR,CHR,RR,RRR,HR,AR,BWR,MA,MUR,PR';
        final res = await ApiClient.get('/api/cards/market', params: {
          'rarities': rarities,
          'sortBy': 'price',
          'sortDir': 'desc',
          'page': 0,
          'size': 50,
        });
        final data = res['data'] as Map<String, dynamic>?;
        result = List<Map<String, dynamic>>.from(data?['content'] ?? []);
      }
      if (!mounted) return;
      setState(() {
        _marketCards = result;
        _loadingMarket = false;
        _loading = false;
      });
      _loadLikedStatuses();
    } catch (_) {
      if (mounted) setState(() { _loadingMarket = false; _loading = false; });
    }
  }

  /// 현재 list의 카드들에 대해 찜 여부 batch 조회 → _likedCardIds 갱신.
  Future<void> _loadLikedStatuses() async {
    final cardIds = _marketCards
        .map((c) => c['cardId'] as String?)
        .whereType<String>()
        .toList();
    if (cardIds.isEmpty) return;
    try {
      final res = await ApiClient.get(
        '/api/card-interests/statuses',
        params: {'cardIds': cardIds.join(',')},
      );
      final data = (res['data'] as Map?) ?? const {};
      if (!mounted) return;
      setState(() {
        _likedCardIds.clear();
        data.forEach((k, v) {
          if (v == true) _likedCardIds.add(k as String);
        });
      });
    } catch (_) {}
  }

  /// 하트 토글 — optimistic UI, 실패 시 롤백.
  Future<void> _toggleLike(String cardId) async {
    final wasLiked = _likedCardIds.contains(cardId);
    setState(() {
      if (wasLiked) {
        _likedCardIds.remove(cardId);
      } else {
        _likedCardIds.add(cardId);
      }
    });
    try {
      await ApiClient.post('/api/card-interests/$cardId/toggle', const {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasLiked) {
          _likedCardIds.add(cardId);
        } else {
          _likedCardIds.remove(cardId);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadTrades() async {
    setState(() => _loading = true);
    try {
      // MY > 내 판매 내역 모드 — JWT principal 기반 history endpoint (OPEN/RESERVED/COMPLETED 포함).
      // sellerId 는 backend 가 인증 토큰에서 결정 — frontend extra sellerId 는 API 호출에 사용 X.
      final Map<String, dynamic> res;
      if (widget.filterSellerId != null) {
        res = await ApiClient.getMyHistory(page: 0, size: 20);
      } else {
        final params = <String, dynamic>{'page': 0, 'size': 20};
        if (widget.filterCardId != null) params['cardId'] = widget.filterCardId;
        res = await ApiClient.get('/api/trades', params: params);
      }
      final data = res['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _trades = List<Map<String, dynamic>>.from(data?['content'] ?? []);
        _hasMore = !(data?['last'] as bool? ?? true);
        _page = 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final Map<String, dynamic> res;
      if (widget.filterSellerId != null) {
        res = await ApiClient.getMyHistory(page: _page + 1, size: 20);
      } else {
        final params = <String, dynamic>{'page': _page + 1, 'size': 20};
        if (widget.filterCardId != null) params['cardId'] = widget.filterCardId;
        res = await ApiClient.get('/api/trades', params: params);
      }
      final data = res['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _trades.addAll(List<Map<String, dynamic>>.from(data?['content'] ?? []));
        _hasMore = !(data?['last'] as bool? ?? true);
        _page++;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // main_shell BottomNav 위에 검정 빈 공간이 생기던 원인:
      // child Scaffold가 default true로 viewInsets만큼 body를 줄여서.
      resizeToAvoidBottomInset: false,
      appBar: _isMainTab
          ? AppBar(
              title: const Text('거래'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: _openSearch,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : AppBar(
              leading: const BackButton(color: AppColors.textPrimary),
              foregroundColor: AppColors.textPrimary,
              title: Text(
                widget.title ??
                    (widget.filterCardName != null
                        ? '${widget.filterCardName} 판매글'
                        : '판매 목록'),
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isMainTab) ...[
            _buildSortTabs(),
          ],
          Expanded(
            child: _isMainTab ? _buildMarketList() : _buildBody(),
          ),
        ],
      ),
    );
  }

  // 정렬 sub-tab (시세/인기/급상승/급하락) + 시세 탭에서만 레어도 dropdown chip
  Widget _buildSortTabs() {
    final tabs = ['시세', '인기', '급상승', '급하락'];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...List.generate(tabs.length, (i) {
              final sel = _sortTab == i;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _sortTab = i);
                    _loadMarketCards();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.blue : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? AppColors.blue : AppColors.divider),
                    ),
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        color: sel ? Colors.white : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }),
            // 시세 탭 한정 — 가격 정렬(_sortTab==0)일 때만 노출.
            // 인기/급상승/급하락은 endpoint 자체가 rarities param 미지원 → A안 (시세 전용).
            if (_sortTab == 0) _buildRarityChip(),
          ],
        ),
      ),
    );
  }

  /// 레어도 dropdown chip — 시세 탭에서만 노출.
  /// 선택 상태(`_selectedRarity != null`)면 chip이 파란색 active + label에 레어도 코드 표시.
  Widget _buildRarityChip() {
    final selected = _selectedRarity != null;
    final label = _selectedRarity ?? '레어도';
    return GestureDetector(
      onTap: _showRarityPicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.blue : AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// 레어도 picker bottom sheet — 단일 선택, '전체' 항목으로 reset.
  /// 옵션 순서 (사용자 합의): PR을 먼저 노출 (마리오 피카츄 등 상위권 PR 카드가 탐색 빈도 ↑),
  /// 이후 일반 레어도 높은 순. PR은 프로모 분류라 일반 레어도 체계와 별도이므로 시트 하단 안내문.
  void _showRarityPicker() {
    const rarityOptions = [
      'PR',
      'BWR',
      'MUR',
      'SAR',
      'UR',
      'HR',
      'SSR',
      'CSR',
      'SR',
      'AR',
      'CHR',
      'ACE',
      'RRR',
      'RR',
    ];
    showModalBottomSheet(
      context: context,
      // MainShell의 centerDocked 스캐너 FAB가 nested Navigator 안 sheet 위에 그려져
      // 시트 하단(PR 안내문/마지막 옵션)을 가리는 문제 방지 — root navigator로 push.
      useRootNavigator: true,
      backgroundColor: AppColors.surfaceCard,
      // default 50% height 제한 풀어서 14개 옵션 + PR 안내문이 한 화면에 다 보이게.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // grab handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '레어도 필터',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            // 스크롤 가능한 옵션 영역 — 안내문이 항상 보이게 시트 하단에 고정.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _rarityPickerTile(sheetCtx, label: '전체', value: null),
                    ...rarityOptions.map(
                      (r) => _rarityPickerTile(sheetCtx, label: r, value: r),
                    ),
                  ],
                ),
              ),
            ),
            // PR 별도 분류 안내 — 시트 항상 하단.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.dividerSoft)),
              ),
              child: const Text(
                'PR은 프로모 카드로, 일반 레어도 순서와 별도 분류입니다.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 레어도 항목 1개 — 선택 중이면 체크 아이콘.
  Widget _rarityPickerTile(BuildContext sheetCtx, {required String label, required String? value}) {
    final isSelected = _selectedRarity == value;
    return InkWell(
      onTap: () {
        Navigator.pop(sheetCtx);
        if (_selectedRarity != value) {
          setState(() => _selectedRarity = value);
          _loadMarketCards();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.blueLight : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded, color: AppColors.blueLight, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketList() {
    if (_loadingMarket) {
      return const Center(child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2));
    }
    final cards = _marketCards;
    if (cards.isEmpty) {
      return _buildEmptyMarketState();
    }
    return RefreshIndicator(
      onRefresh: _loadMarketCards,
      color: AppColors.blue,
      backgroundColor: AppColors.surface,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.dividerSoft, indent: 78),
        itemBuilder: (ctx, i) {
          final card = cards[i];
          return _buildMarketCardRow(card, i + 1);
        },
      ),
    );
  }

  /// 빈 상태 — 마켓 비어있음일 때만 (검색은 풀스크린 분리됨).
  /// 시세 탭에서 레어도 필터가 켜진 채 결과 0개면 안내 문구를 다르게 표시.
  Widget _buildEmptyMarketState() {
    final isRarityFiltered = _sortTab == 0 && _selectedRarity != null;
    final title = isRarityFiltered
        ? '"${_selectedRarity!}" 레어도 카드가 없습니다'
        : '카드가 없습니다';
    final subtitle = isRarityFiltered
        ? '레어도 필터를 해제하거나 다른 레어도를 선택해 보세요'
        : '우상단 돋보기를 눌러 카드를 검색해 보세요';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.storefront_outlined,
              color: AppColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (isRarityFiltered) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() => _selectedRarity = null);
                  _loadMarketCards();
                },
                child: const Text(
                  '전체로 보기',
                  style: TextStyle(
                    color: AppColors.blueLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 카드 list row — 토스 종목 list 패턴 (이미지 + 이름 + 시세 + 변동률)
  Widget _buildMarketCardRow(Map<String, dynamic> card, int rank) {
    final cardId = card['cardId'] as String? ?? '';
    final name = card['name'] as String? ?? '';
    final price = (card['koEstimatedPrice'] as num?)?.toInt() ??
        (card['latestPrice'] as num?)?.toInt();
    final pct = (card['gainPct'] as num?)?.toDouble();
    final liked = _likedCardIds.contains(cardId);
    // 시세 정렬일 때만 랭킹 번호 (다른 정렬은 misleading)
    final showRank = _sortTab == 0;

    // PriceDisplayPolicy (2026-05-16): 저가 카드 % 숨김/Stage B 전체 숨김/Stage C 변동 적음
    // API에 prevPrice가 없어서 price + pct로 역산 후 정책 판단
    int? prevPriceApprox;
    if (price != null && pct != null && pct > -100) {
      prevPriceApprox = (price / (1 + pct / 100)).round();
    }
    final display = PriceDisplayPolicy.buildChangeDisplay(
      lastPrice: price,
      prevPrice: prevPriceApprox,
      prefix: '',
    );
    final String pctLabel = display?.label.trim() ?? '';
    final Color pctColor = display == null
        ? AppColors.textMuted
        : switch (display.color) {
            // 색상 정책 (feedback_color_policy.md): 양=빨강, 음=파랑.
            PriceChangeColor.positive => AppColors.red,
            PriceChangeColor.negative => AppColors.blue,
            PriceChangeColor.neutral => AppColors.textMuted,
          };

    return InkWell(
      onTap: () async {
        await context.push('/card/$cardId', extra: {'cardData': card});
        if (mounted) _loadMarketCards();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (showRank) ...[
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: AppColors.blue.withValues(alpha: rank <= 3 ? 1.0 : 0.5),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // 카드 thumbnail — 직사각형 유지 (원형 crop은 카드 아트 잘림)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CardImage(
                imageUrl: resolveCardImageUrl(card),
                width: 44,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            // 카드명+rarity(위) → 가격·변동률(중간) → 거래 시그널(아래) 3행 패턴.
            // Phase 1: rarity badge + 매도/매수/관심 카운트. count는 null-safe(0).
            Expanded(
              child: Builder(builder: (_) {
                final rarityCode = (card['rarityCode'] as String?) ?? '';
                final sell = (card['activeSellCount'] as num?)?.toInt() ?? 0;
                final buy = (card['activeBuyCount'] as num?)?.toInt() ?? 0;
                final interest = (card['interestCount'] as num?)?.toInt() ?? 0;
                final priceLabelText = PriceLabel.resolve(
                  labelType: card['koPriceLabelType'] as String?,
                  price: price,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (rarityCode.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _rarityPill(rarityCode),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          price != null ? AppColors.formatPrice(price) : '시세 없음',
                          style: TextStyle(
                            color: price != null
                                ? AppColors.textSecondary
                                : AppColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 가격 옆 inline 라벨 — 국내 예상가 / 해외 참고가 / 시세 준비중.
                        Text(
                          priceLabelText,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          pctLabel,
                          style: TextStyle(
                            color: pctColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 거래 시그널 — 색 정책: 매도=blue(호가창 ASK 컨벤션), 매수=red(BID), 관심=neutral.
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        children: [
                          TextSpan(
                            text: '매도 $sell',
                            style: const TextStyle(color: AppColors.blue),
                          ),
                          const TextSpan(text: '  ·  ', style: TextStyle(color: AppColors.textMuted)),
                          TextSpan(
                            text: '매수 $buy',
                            style: const TextStyle(color: AppColors.red),
                          ),
                          const TextSpan(text: '  ·  ', style: TextStyle(color: AppColors.textMuted)),
                          TextSpan(
                            text: '관심 $interest',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ),
            // 하트 — 카드 단위 찜 토글
            GestureDetector(
              onTap: () => _toggleLike(cardId),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? AppColors.red : AppColors.textMuted,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// rarity 작은 회색 pill — name 옆 짧은 badge (과하지 않게).
  Widget _rarityPill(String code) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Text(
          code,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      );

  /// 풀스크린 검색 모달 push — 화면 전환 애니메이션이 iOS 키보드 cold-start lag을 가려줌.
  void _openSearch() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => const TradeSearchScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2),
      );
    }
    if (_trades.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.storefront_outlined,
              color: AppColors.textMuted,
              size: 52,
            ),
            const SizedBox(height: 14),
            Text(
              _isMainTab ? '아직 판매 중인 카드가 없습니다' : '등록된 판매 카드가 없습니다',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadTrades,
      color: AppColors.blue,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: _trades.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _trades.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: AppColors.blue,
                  strokeWidth: 2,
                ),
              ),
            );
          }
          return _buildTradeCard(_trades[i]);
        },
      ),
    );
  }

  String _timeAgo(String ts) {
    if (ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '방금';
      if (diff.inHours < 1) return '${diff.inMinutes}분 전';
      if (diff.inDays < 1) return '${diff.inHours}시간 전';
      if (diff.inDays < 7) return '${diff.inDays}일 전';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return ts.length >= 10 ? ts.substring(0, 10) : ts;
    }
  }

  Widget _buildTradeCard(Map<String, dynamic> trade) {
    final tradeId = trade['tradeId'] ?? '';
    final title = trade['title'] ?? '';
    final price = trade['price'] as num?;
    final cardData =
        (trade['card'] is Map
            ? Map<String, dynamic>.from(trade['card'] as Map)
            : null) ??
        {};
    final rarity = cardData['rarityCode'] as String? ?? '';
    // 사용자 업로드 사진은 /api/images/secure/{key} proxy — JWT 인증 필수라 AuthImage 사용.
    // CardImage(단순 Image.network)로 호출하면 401 → placeholder. 호가창은 이미 AuthImage 사용.
    final imageUrls = (trade['imageUrls'] as List?)?.cast<dynamic>() ?? const [];
    final firstTradeImage = imageUrls
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .firstOrNull;
    final tradeUploadUrl = (firstTradeImage != null)
        ? (firstTradeImage.startsWith('http')
            ? firstTradeImage
            : ApiConstants.tradeImageUrl(firstTradeImage))
        : null;
    final cardFallbackUrl =
        tradeUploadUrl == null ? resolveCardImageUrl(cardData) : null;
    final sellerData =
        (trade['seller'] is Map
            ? Map<String, dynamic>.from(trade['seller'] as Map)
            : null) ??
        {};
    final sellerNickname = sellerData['nickname'] as String? ?? '';
    final createdAt = trade['createdAt'] as String? ?? '';
    final tradeStatus = trade['status'] as String? ?? 'OPEN';
    final condition = trade['condition'] as String?;
    final conditionScore = condition != null
        ? double.tryParse(condition)
        : null;
    final glowColor = AppColors.rarityGlow(rarity);
    final hasGlow = rarity.isNotEmpty && glowColor != Colors.transparent;

    return GestureDetector(
      onTap: () async {
        final changed = await context.push<bool>('/trades/$tradeId');
        if (changed == true && mounted) _loadTrades();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasGlow
                ? glowColor.withValues(alpha: 0.2)
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                  child: tradeUploadUrl != null
                      ? AuthImage(
                          url: tradeUploadUrl,
                          width: 80,
                          height: 108,
                          fit: BoxFit.cover,
                        )
                      : CardImage(
                          imageUrl: cardFallbackUrl,
                          width: 80,
                          height: 108,
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.zero,
                        ),
                ),
                if (tradeStatus != 'OPEN')
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(14),
                      ),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: Center(
                          child: Text(
                            switch (tradeStatus) {
                              'RESERVED' => '거래중',
                              'COMPLETED' => '거래 완료',
                              'DELETED' => '삭제됨',
                              _ => '판매완료',
                            },
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (rarity.isNotEmpty) _RarityTag(rarity: rarity),
                        if (conditionScore != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '앱분석 ${conditionScore.toStringAsFixed(1)}점',
                              style: const TextStyle(
                                color: AppColors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      price != null
                          ? AppColors.formatPrice(price.toInt())
                          : '가격 협의',
                      style: TextStyle(
                        color: price != null
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (sellerNickname.isNotEmpty) ...[
                          Text(
                            sellerNickname,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          const Text(
                            ' · ',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        Text(
                          _timeAgo(createdAt),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        // 조회수는 판매자 관리 화면(내 판매 항목)에만 표시.
                        // 일반 거래 리스트(다른 사용자 글)는 채팅·관심만 표시.
                        if (widget.filterSellerId != null &&
                            (trade['viewCount'] as num? ?? 0) > 0) ...[
                          const Text(
                            ' · ',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          const Icon(
                            Icons.visibility_outlined,
                            color: AppColors.textMuted,
                            size: 11,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${trade['viewCount']}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        // 채팅 수 / 관심 수 — 0이면 숨김.
                        if ((trade['chatCount'] as num? ?? 0) > 0) ...[
                          const Text(' · ',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                          const Icon(Icons.chat_bubble_outline_rounded,
                              color: AppColors.textMuted, size: 11),
                          const SizedBox(width: 2),
                          Text('${trade['chatCount']}',
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                        ],
                        if ((trade['favoriteCount'] as num? ?? 0) > 0) ...[
                          const Text(' · ',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                          const Icon(Icons.favorite_border_rounded,
                              color: AppColors.textMuted, size: 11),
                          const SizedBox(width: 2),
                          Text('${trade['favoriteCount']}',
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RarityTag extends StatelessWidget {
  final String rarity;
  const _RarityTag({required this.rarity});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        rarity,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
