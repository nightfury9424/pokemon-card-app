import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/price_display_policy.dart';
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
  int _reqId = 0;

  bool _loading = false;
  List<Map<String, dynamic>> _cards = [];
  String _query = '';
  List<String> _recents = [];
  // 자동완성 suggestions (가벼운 /api/cards/search). suggestion 탭 시 _showCards=true로 본격 검색.
  List<String> _suggestions = [];
  bool _showCards = false;

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
    final id = ++_reqId;
    try {
      final res = await ApiClient.get(
        '/api/cards/search',
        params: {'name': query},
      );
      if (!mounted || id != _reqId || query != _query.trim()) return;
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
    _focusNode.unfocus();
    _controller.text = q;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: q.length));
    setState(() {
      _query = q;
      _showCards = true;
      _loading = true;
    });
    await _saveRecent(q);
    final id = ++_reqId;
    try {
      final res = await ApiClient.get('/api/cards/market', params: {
        'name': q,
        'sortBy': 'price',
        'sortDir': 'desc',
        'page': 0,
        'size': 200,
        'rarities': _rarities,
      });
      if (!mounted || id != _reqId) return;
      final data = res['data'] as Map<String, dynamic>?;
      final list = List<Map<String, dynamic>>.from(data?['content'] ?? []);
      setState(() {
        _cards = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _reqId) return;
      setState(() => _loading = false);
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
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                            ),
                            decoration: const InputDecoration(
                              hintText: '카드명 / 세트 / 등급으로 검색',
                              hintStyle: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: _onChanged,
                            onSubmitted: (v) {
                              // ↵ 누르면: 자동완성 첫 항목 있으면 그걸로, 없으면 입력 그대로 검색.
                              final picked = _suggestions.isNotEmpty
                                  ? _suggestions.first
                                  : v.trim();
                              if (picked.isNotEmpty) _runCardSearch(picked);
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

  Widget _buildRow(Map<String, dynamic> card, int rank) {
    final cardId = card['cardId'] as String? ?? '';
    final name = card['name'] as String? ?? '';
    final rarity = card['rarityCode'] as String? ?? '';
    final price = (card['koEstimatedPrice'] as num?)?.toInt() ??
        (card['latestPrice'] as num?)?.toInt();
    final pct = (card['gainPct'] as num?)?.toDouble();
    final rarityColor = AppColors.rarityColor(rarity);
    return InkWell(
      onTap: () async {
        _focusNode.unfocus();
        // 최근 검색은 _runCardSearch에서 이미 저장됨 — 카드 탭은 진입만.
        await context.push('/card/$cardId', extra: {'cardData': card});
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
                  color: AppColors.blue
                      .withValues(alpha: rank <= 3 ? 1.0 : 0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CardImage(
                imageUrl: resolveCardImageUrl(card),
                cdnFallbackUrl: resolveCdnImageUrl(card),
                width: 56,
                height: 78,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (rarity.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: rarityColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            rarity,
                            style: TextStyle(
                              color: rarityColor,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      if (price == null) ...[
                        const SizedBox(width: 6),
                        const Text(
                          '시세 없음',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price != null ? AppColors.formatPrice(price) : '-',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Builder(builder: (_) {
                  // PriceDisplayPolicy (2026-05-16): 저가 카드 % 숨김/Stage B 전체 숨김/Stage C 변동 적음
                  int? prevPriceApprox;
                  if (price != null && pct != null && pct > -100) {
                    prevPriceApprox = (price / (1 + pct / 100)).round();
                  }
                  final display = PriceDisplayPolicy.buildChangeDisplay(
                    lastPrice: price,
                    prevPrice: prevPriceApprox,
                    prefix: '',
                  );
                  if (display == null) {
                    return const Text(
                      '-',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    );
                  }
                  // scanner와 동일한 한국 주식 패턴 (양수=빨강, 음수=파랑)
                  final color = switch (display.color) {
                    PriceChangeColor.positive => AppColors.red,
                    PriceChangeColor.negative => AppColors.blue,
                    PriceChangeColor.neutral => AppColors.textMuted,
                  };
                  return Text(
                    display.label.trim(),
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
