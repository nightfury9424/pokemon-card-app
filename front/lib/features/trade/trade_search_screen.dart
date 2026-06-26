import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/price_display_policy.dart';
import '../../core/utils/price_label.dart';
import '../../core/widgets/card_image.dart';

/// 거래 탭 검색 — 풀스크린 모달.
/// 거래 탭의 검색 아이콘에서 push. 화면 전환 애니메이션이 iOS 키보드 cold-start lag을 가려줌.
class TradeSearchScreen extends StatefulWidget {
  const TradeSearchScreen({super.key});

  @override
  State<TradeSearchScreen> createState() => _TradeSearchScreenState();
}

class _TradeSearchScreenState extends State<TradeSearchScreen> {
  static const _rarities =
      'SR,SSR,SAR,RR,RRR,AR,HR,PR,UR,SM-P,CHR,CSR,H,A,P,MA,MUR,BWR';
  static const _recentsKey = 'recent_card_searches';
  static const _maxRecents = 10;
  static const _storage = FlutterSecureStorage();

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  // 자동완성/카드검색 별도 카운터 — 공유 시 뒤늦은 suggestion이 검색 응답을
  // stale 처리해 _loading 영구 true(무한 스피너) 되던 버그 방지.
  int _suggestReqId = 0;
  int _searchReqId = 0;

  bool _loading = false;
  List<Map<String, dynamic>> _cards = [];
  String _query = '';
  List<String> _recents = [];
  // 자동완성 suggestions (가벼운 /api/cards/search). suggestion 탭 시 _showCards=true로 본격 검색.
  List<String> _suggestions = [];
  bool _showCards = false;
  // 카드 단위 찜(관심) 상태 — 거래 리스트와 동일 패턴(/api/card-interests).
  final Set<String> _likedCardIds = {};

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    try {
      final raw = await _storage.read(key: _recentsKey);
      if (raw == null || !mounted) return;
      final list = raw
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      setState(() => _recents = list);
    } catch (_) {}
  }

  Future<void> _saveRecent(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final updated = [
      q,
      ..._recents.where((s) => s != q),
    ].take(_maxRecents).toList();
    if (!mounted) return;
    setState(() => _recents = updated);
    try {
      await _storage.write(key: _recentsKey, value: updated.join('\n'));
    } catch (_) {}
  }

  Future<void> _clearRecents() async {
    if (!mounted) return;
    setState(() => _recents = []);
    try {
      await _storage.delete(key: _recentsKey);
    } catch (_) {}
  }

  Future<void> _removeRecent(String query) async {
    if (!mounted) return;
    final updated = _recents.where((s) => s != query).toList();
    setState(() => _recents = updated);
    try {
      if (updated.isEmpty) {
        await _storage.delete(key: _recentsKey);
      } else {
        await _storage.write(key: _recentsKey, value: updated.join('\n'));
      }
    } catch (_) {}
  }

  void _applyRecent(String query) {
    // 최근 검색 chip 탭 → 자동완성 거치지 않고 바로 카드 결과로.
    _runCardSearch(query);
  }

  void _onChanged(String value) {
    setState(() {
      _query = value;
      _showCards = false;
      if (value.trim().isEmpty) {
        _suggestions = [];
        _cards = [];
      }
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _loadSuggestions();
    });
  }

  /// 카드명 자동완성 — 가벼운 /api/cards/search로 이름만 가져와 unique normalize.
  /// 응답: {status, data: [...]}. `getList`는 root 배열용이라 빈 list 받음 → ApiClient.get 사용.
  Future<void> _loadSuggestions() async {
    final query = _query.trim();
    if (query.isEmpty) return;
    final id = ++_suggestReqId;
    try {
      final res = await ApiClient.get(
        '/api/cards/search',
        params: {'name': query},
      );
      if (!mounted || id != _suggestReqId || query != _query.trim()) return;
      final list = (res['data'] as List?) ?? const [];
      final names = <String>{};
      for (final item in list) {
        if (item is! Map) continue;
        final raw = item['name']?.toString() ?? '';
        final n = _normalize(raw);
        if (n.isNotEmpty) names.add(n);
      }
      setState(() => _suggestions = names.take(20).toList());
    } catch (_) {}
  }

  /// 카드명에서 suffix(EX/ex/V/VMAX/GX 등) 제거 → 같은 캐릭터 묶음.
  String _normalize(String name) {
    return name
        .replaceAll(
          RegExp(r'\s+(EX|ex|V|VMAX|VSTAR|VUNION|GX|BREAK).*$'),
          '',
        )
        .trim();
  }

  Future<void> _runCardSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    // 검색 실행 = 자동완성 흐름 종료 → pending suggestion debounce 취소.
    _debounce?.cancel();
    _focusNode.unfocus();
    _controller.text = q;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: q.length));
    // ★검색 전용 id를 setState/네트워크 전에 확보 (suggestion과 분리).
    final id = ++_searchReqId;
    setState(() {
      _query = q;
      _showCards = true;
      _loading = true;
    });
    // storage write가 검색 시작/완료를 막지 않게 (await 제거).
    unawaited(_saveRecent(q));
    try {
      final res = await ApiClient.get('/api/cards/market', params: {
        'name': q,
        'sortBy': 'price',
        'sortDir': 'desc',
        'page': 0,
        'size': 200,
        'rarities': _rarities,
      });
      if (!mounted || id != _searchReqId) return;
      final data = res['data'] as Map<String, dynamic>?;
      final list = List<Map<String, dynamic>>.from(data?['content'] ?? []);
      setState(() => _cards = list);
      _loadLikedStatuses(id);
    } catch (_) {
      // 에러 시 _loading 정리는 finally에서 (빈 결과 화면 노출).
    } finally {
      // ★최신 검색일 때만 _loading 해제 — stale guard 밖이라 무한 스피너 원천 차단.
      if (mounted && id == _searchReqId) {
        setState(() => _loading = false);
      }
    }
  }

  /// 검색 결과 카드들 찜 여부 batch 조회.
  Future<void> _loadLikedStatuses(int searchId) async {
    final cardIds = _cards
        .map((c) => c['cardId'] as String?)
        .whereType<String>()
        .toList();
    if (cardIds.isEmpty) return;
    try {
      final res = await ApiClient.get(
        '/api/card-interests/statuses',
        params: {'cardIds': cardIds.join(',')},
      );
      // ★늦게 온 예전 검색의 찜 응답이 새 결과 _likedCardIds를 덮지 않게.
      if (!mounted || searchId != _searchReqId) return;
      final data = (res['data'] as Map?) ?? const {};
      setState(() {
        _likedCardIds.clear();
        data.forEach((k, v) {
          if (v == true) _likedCardIds.add(k as String);
        });
      });
    } catch (_) {}
  }

  /// 하트 토글 — optimistic, 실패 시 롤백.
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: AppColors.textPrimary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            color: AppColors.textMuted, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            textAlignVertical: TextAlignVertical.center,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                            ),
                            decoration: const InputDecoration(
                              hintText: '카드명 또는 세트명으로 검색',
                              hintStyle: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: _onChanged,
                            onSubmitted: (v) {
                              // ↵ = 입력한 그대로 검색 (자동완성 최상위로 치환 X).
                              // 연관검색어는 탭했을 때만 적용 — "피카" Enter → "피카" 검색.
                              final q = v.trim();
                              if (q.isNotEmpty) _runCardSearch(q);
                            },
                          ),
                        ),
                        if (_query.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _controller.clear();
                              _onChanged('');
                            },
                            child: const Icon(
                              Icons.close_rounded,
                              color: AppColors.textMuted,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2),
      );
    }
    final q = _query.trim();
    if (q.isEmpty) return _buildHintEmptyState();
    // 입력 중 → 자동완성 list. suggestion/↵/recent 탭 후 → 카드 결과.
    if (!_showCards) return _buildSuggestions();
    if (_cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.search_off_rounded,
                  color: AppColors.textMuted, size: 40),
              SizedBox(height: 10),
              Text(
                '검색 결과가 없습니다',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
      itemCount: _cards.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.dividerSoft, indent: 78),
      itemBuilder: (ctx, i) => _buildRow(_cards[i], i + 1),
    );
  }

  /// 자동완성 suggestions — 텍스트만, 가볍게 표시. 탭 시 본격 카드 검색.
  Widget _buildSuggestions() {
    if (_suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Text(
            '"$_query" 관련 카드가 없습니다',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      itemCount: _suggestions.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        color: AppColors.dividerSoft,
        indent: 52,
      ),
      itemBuilder: (ctx, i) {
        final s = _suggestions[i];
        return InkWell(
          onTap: () => _runCardSearch(s),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    color: AppColors.textMuted, size: 18),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    s,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // ↖ 아이콘: 검색바에 채우기만 (자동완성 계속).
                    _controller.text = s;
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: s.length),
                    );
                    _onChanged(s);
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.north_west_rounded,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 빈 상태 — 키보드에 가려지지 않도록 상단 정렬. 최근 검색 + 안내 카드.
  Widget _buildHintEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_recents.isNotEmpty) ...[
            Row(
              children: [
                const Text(
                  '최근 검색',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearRecents,
                  child: const Text(
                    '전체 삭제',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recents.map(_buildRecentChip).toList(),
            ),
            const SizedBox(height: 24),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    Icon(Icons.search_rounded,
                        color: AppColors.blue, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '카드를 검색해 보세요',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '카드를 검색해 종목 페이지에서 판매 / 구매 호가를 등록해 보세요.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentChip(String query) {
    return GestureDetector(
      onTap: () => _applyRecent(query),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              query,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _removeRecent(query),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  color: AppColors.textMuted,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // rarity pill — 거래 리스트(_rarityPill)와 동일.
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

  // 검색 결과 행 — 거래 시세 리스트(_buildMarketCardRow)와 동일 레이아웃
  //   (CardThumb 44x60 + 이름/rarity → 가격+라벨+변동 → 매도·매수·관심 + 하트).
  Widget _buildRow(Map<String, dynamic> card, int rank) {
    final cardId = card['cardId'] as String? ?? '';
    final name = card['name'] as String? ?? '';
    final price = (card['koEstimatedPrice'] as num?)?.toInt() ??
        (card['latestPrice'] as num?)?.toInt();
    final pct = (card['gainPct'] as num?)?.toDouble();
    final liked = _likedCardIds.contains(cardId);

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
            PriceChangeColor.positive => AppColors.red,
            PriceChangeColor.negative => AppColors.blue,
            PriceChangeColor.neutral => AppColors.textMuted,
          };

    return InkWell(
      onTap: () async {
        _focusNode.unfocus();
        await context.push('/card/$cardId', extra: {'cardData': card});
        if (mounted) _loadLikedStatuses(_searchReqId); // 상세에서 찜 토글했을 수 있어 재동기화.
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
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
            CardThumb(
              imageUrl: resolveCardImageUrl(card),
              width: 44,
              height: 60,
            ),
            const SizedBox(width: 14),
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
                    // 가격·예상가라벨·변동 — 고정 Row 대신 Wrap. 좁은 폭/큰 글자배율에서
                    // 변동값이 다음 줄로 흘러 오른쪽 하트와 겹치지 않게 한다(거래 시세 행과 동일 동작).
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
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
                        if (priceLabelText.isNotEmpty)
                          Text(
                            priceLabelText,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (pctLabel.isNotEmpty)
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
            // 하트 — 카드 단위 찜 토글 (거래 리스트와 동일).
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
}
