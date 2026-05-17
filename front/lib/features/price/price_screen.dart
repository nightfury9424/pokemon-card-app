import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

enum _SortMode { name, rarity, price }

class PriceScreen extends StatefulWidget {
  const PriceScreen({super.key});

  @override
  State<PriceScreen> createState() => _PriceScreenState();
}

class _PriceScreenState extends State<PriceScreen> {
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  int _totalElements = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  _SortMode _sortMode = _SortMode.price;
  bool _sortAscending = false;
  String? _selectedRarity;

  static const _pageSize = 50;
  static const _allRarities = ['SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'UR', 'SR', 'AR', 'HR', 'ACE', 'RRR', 'RR', 'PR', 'MA', 'MUR'];

  String get _raritiesParam => _selectedRarity ?? _allRarities.join(',');

  String get _sortByParam => switch (_sortMode) {
    _SortMode.name   => 'name',
    _SortMode.rarity => 'rarity',
    _SortMode.price  => 'price',
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadCards();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400 &&
        !_loadingMore && _hasMore && !_loading) {
      _loadMore();
    }
  }

  Future<void> _loadCards() async {
    setState(() { _loading = true; _page = 0; _hasMore = true; });
    final snapshot = _searchQuery;
    try {
      final mainFuture = ApiClient.get('/api/cards/market', params: {
        'rarities': _raritiesParam,
        'name': snapshot,
        'page': 0,
        'size': _pageSize,
        'sortBy': _sortByParam,
        'sortDir': _sortAscending ? 'asc' : 'desc',
      });
      final res = await mainFuture;
      if (snapshot != _searchQuery) return;
      final data = res['data'] as Map<String, dynamic>;
      final content = List<Map<String, dynamic>>.from(data['content'] ?? []);
      final total = (data['totalElements'] as num?)?.toInt() ?? 0;
      final totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      setState(() {
        _cards = content;
        _totalElements = total;
        _hasMore = totalPages > 1;
        _page = 0;
        _loading = false;
      });
    } catch (e) {
      if (snapshot == _searchQuery) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final res = await ApiClient.get('/api/cards/market', params: {
        'rarities': _raritiesParam,
        'name': _searchQuery,
        'page': nextPage,
        'size': _pageSize,
        'sortBy': _sortByParam,
        'sortDir': _sortAscending ? 'asc' : 'desc',
      });
      final data = res['data'] as Map<String, dynamic>;
      final content = List<Map<String, dynamic>>.from(data['content'] ?? []);
      final totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      setState(() {
        _cards = [..._cards, ...content];
        _page = nextPage;
        _hasMore = nextPage + 1 < totalPages;
        _loadingMore = false;
      });
    } catch (e) {
      setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String value) {
    _searchDebounce?.cancel();
    setState(() => _searchQuery = value);
    _searchDebounce = Timer(const Duration(milliseconds: 500), _loadCards);
  }

  void _onSortTap(_SortMode mode) {
    setState(() {
      if (_sortMode == mode) {
        _sortAscending = !_sortAscending;
      } else {
        _sortMode = mode;
        _sortAscending = mode == _SortMode.price ? false : true;
      }
    });
    _loadCards();
  }

  void _onRarityTap(String rarity) {
    setState(() => _selectedRarity = _selectedRarity == rarity ? null : rarity);
    _loadCards();
  }

  bool _hasScrydexRef(Object? ref) {
    final value = ref as String?;
    return value != null && value.isNotEmpty && !value.startsWith('NO_');
  }

  String _priceLabel(Map<String, dynamic> card) {
    final isPromoExclusive = card['isPromoExclusive'] == true;
    if (!isPromoExclusive) return 'KO 예상 가치';

    final basis = card['koPriceBasis'] as String?;
    if (basis == 'PSA10') return 'JP 시세 (PSA10 기준)';

    final hasJpRef = _hasScrydexRef(card['jpScrydexRef']);
    final hasEnRef = _hasScrydexRef(card['enScrydexRef']);
    if (hasJpRef) return 'JP 시세';
    if (hasEnRef) return 'EN 시세';
    return 'KO 예상 가치';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          _buildFilterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2))
                : _cards.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty ? '카드가 없습니다' : '"$_searchQuery" 검색 결과 없음',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCards,
                        color: AppColors.blue,
                        backgroundColor: AppColors.surface,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.only(
                            bottom: 16 + MediaQuery.of(context).padding.bottom,
                          ),
                          itemCount: _cards.length +
                              (_hasMore || _loadingMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _cards.length) {
                              return Padding(
                                padding: const EdgeInsets.all(20),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2)
                                      : const SizedBox.shrink(),
                                ),
                              );
                            }
                            return _buildCardRow(_cards[i]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(
          children: [
            const Text(
              '시세',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            Text(
              _totalElements > 0 ? '$_totalElements종' : '',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '카드명 검색',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: _onSearch,
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _onSearch('');
                },
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close_rounded, color: AppColors.textMuted, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Column(
      children: [
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _SortChip(label: '가격순', mode: _SortMode.price, current: _sortMode, asc: _sortAscending, onTap: _onSortTap),
              const SizedBox(width: 8),
              _SortChip(label: '등급순', mode: _SortMode.rarity, current: _sortMode, asc: _sortAscending, onTap: _onSortTap),
              const SizedBox(width: 8),
              _SortChip(label: '이름순', mode: _SortMode.name, current: _sortMode, asc: _sortAscending, onTap: _onSortTap),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _allRarities.map((r) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _RarityChip(rarity: r, selected: _selectedRarity == r, onTap: _onRarityTap),
            )).toList(),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildCardRow(Map<String, dynamic> card) {
    final cardId = card['cardId'] as String? ?? '';
    final name = card['name'] as String? ?? '';
    final rarity = card['rarityCode'] as String? ?? '';
    final setName = card['productName'] as String?
        ?? card['seriesName'] as String?;
    final koPrice = (card['koEstimatedPrice'] as num?)?.toInt()
        ?? (card['latestPrice'] as num?)?.toInt();
    final priceLabel = _priceLabel(card);
    final imageUrl = resolveCardImageUrl(card);
    final cdnUrl = resolveCdnImageUrl(card);
    final glowColor = AppColors.rarityGlow(rarity);
    final hasGlow = rarity.isNotEmpty && glowColor != Colors.transparent;

    return GestureDetector(
      onTap: () => context.push('/card/$cardId', extra: card),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasGlow ? glowColor.withValues(alpha: 0.25) : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CardImage(
                imageUrl: imageUrl,
                cdnFallbackUrl: cdnUrl,
                width: 44,
                height: 62,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rarity.isNotEmpty) _RarityTag(rarity: rarity),
                      if (rarity.isNotEmpty && setName != null) const SizedBox(width: 6),
                      if (setName != null)
                        Flexible(
                          child: Text(
                            setName,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
                  koPrice != null ? AppColors.formatPrice(koPrice) : '-',
                  style: TextStyle(
                    color: koPrice != null ? AppColors.textPrimary : AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(priceLabel, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final _SortMode mode;
  final _SortMode current;
  final bool asc;
  final void Function(_SortMode) onTap;

  const _SortChip({
    required this.label,
    required this.mode,
    required this.current,
    required this.asc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = mode == current;
    return GestureDetector(
      onTap: () => onTap(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue.withValues(alpha: 0.15) : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.blue.withValues(alpha: 0.5) : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.blue : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 2),
              Icon(
                asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 11,
                color: AppColors.blue,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RarityChip extends StatelessWidget {
  final String rarity;
  final bool selected;
  final void Function(String) onTap;

  const _RarityChip({required this.rarity, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.rarityColor(rarity);
    return GestureDetector(
      onTap: () => onTap(rarity),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : AppColors.divider),
        ),
        child: Text(
          rarity,
          style: TextStyle(
            color: selected ? color : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        rarity,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
