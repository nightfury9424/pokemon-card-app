import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/widgets/card_image.dart';

enum _SortMode { name, rarity, price, date }

class PriceScreen extends StatefulWidget {
  const PriceScreen({super.key});

  @override
  State<PriceScreen> createState() => _PriceScreenState();
}

class _PriceScreenState extends State<PriceScreen> {
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  _SortMode _sortMode = _SortMode.name;
  bool _sortAscending = true;
  String? _selectedRarity; // null = 전체

  // 포켓몬 카드 등급 순서: 높은 등급 → 낮은 등급
  static const _allRarities = ['SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'UR', 'SR', 'AR', 'HR', 'ACE', 'RRR', 'RR', 'PR', 'H', 'MA', 'MUR'];
  static const _rarityOrder = {
    'SSR': 0, 'SAR': 1, 'BWR': 2, 'CSR': 3, 'CHR': 4, 'UR': 5, 'SR': 6, 'AR': 7,
    'HR': 8, 'ACE': 9, 'RRR': 10, 'RR': 11, 'PR': 12, 'H': 13, 'MA': 14, 'MUR': 15,
  };

  String get _raritiesParam => _selectedRarity ?? _allRarities.join(',');

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{
        'rarities': _raritiesParam,
        'name': _searchQuery,
        'page': 0,
        'size': 500,
      };
      if (_sortMode == _SortMode.price) params['sortBy'] = 'price';
      final res = await ApiClient.get('/api/cards/market', params: params);
      final data = res['data'] as Map<String, dynamic>;
      final content = List<Map<String, dynamic>>.from(data['content'] ?? []);
      setState(() {
        _cards = content;
        _loading = false;
        _applySortInPlace();
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _applySortInPlace() {
    final asc = _sortAscending ? 1 : -1;
    switch (_sortMode) {
      case _SortMode.name:
        _cards.sort((a, b) =>
            (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? '') * asc);
      case _SortMode.rarity:
        _cards.sort((a, b) {
          final ra = _rarityOrder[a['rarityCode']] ?? 99;
          final rb = _rarityOrder[b['rarityCode']] ?? 99;
          if (ra != rb) return ra.compareTo(rb) * asc;
          return (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? '');
        });
      case _SortMode.price:
        _cards.sort((a, b) {
          final pa = (a['latestPrice'] as num?)?.toInt();
          final pb = (b['latestPrice'] as num?)?.toInt();
          if (pa == null && pb == null) return 0;
          if (pa == null) return 1;  // null 항상 맨 아래
          if (pb == null) return -1;
          return pa.compareTo(pb) * asc;
        });
      case _SortMode.date:
        _cards.sort((a, b) {
          final da = a['latestTradedAt'] as String?;
          final db = b['latestTradedAt'] as String?;
          if (da == null && db == null) return 0;
          if (da == null) return 1;  // null 항상 맨 아래
          if (db == null) return -1;
          return da.compareTo(db) * asc;
        });
    }
  }

  void _onSearch(String value) {
    setState(() => _searchQuery = value);
    _loadCards();
  }

  void _onSortTap(_SortMode mode) {
    final prevMode = _sortMode;
    if (_sortMode == mode) {
      _sortAscending = !_sortAscending;
    } else {
      _sortMode = mode;
      _sortAscending = mode == _SortMode.price ? false : true;
    }
    // 가격순 ↔ 다른 정렬 전환 시 백엔드 재조회
    if (mode == _SortMode.price || prevMode == _SortMode.price) {
      _loadCards();
    } else {
      setState(() => _applySortInPlace());
    }
  }

  void _onRarityTap(String rarity) {
    setState(() {
      _selectedRarity = _selectedRarity == rarity ? null : rarity;
    });
    _loadCards();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('시세 보기'),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildSortRow(),
          _buildRarityRow(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white30))
                : _cards.isEmpty
                    ? const Center(
                        child: Text('카드를 찾을 수 없습니다',
                            style: TextStyle(color: Colors.white38)),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _cards.length,
                        itemBuilder: (context, index) =>
                            _buildCardItem(_cards[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      color: const Color(0xFF1A1A2E),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: '카드명 검색 (예: 리자몽)',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38),
                  onPressed: () {
                    _searchController.clear();
                    _onSearch('');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF16213E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: _onSearch,
      ),
    );
  }

  Widget _buildSortRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Center(child: _buildSortChip('이름순', _SortMode.name)),
          const SizedBox(width: 6),
          Center(child: _buildSortChip('등급순', _SortMode.rarity)),
          const SizedBox(width: 6),
          Center(child: _buildSortChip('가격순', _SortMode.price)),
          const SizedBox(width: 6),
          Center(child: _buildSortChip('날짜순', _SortMode.date)),
        ],
      ),
    );
  }

  Widget _buildRarityRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _allRarities.map((r) => Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _buildRarityChip(r),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildSortChip(String label, _SortMode mode) {
    final selected = _sortMode == mode;
    final arrow = selected ? (_sortAscending ? ' ↑' : ' ↓') : '';
    return GestureDetector(
      onTap: () => _onSortTap(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4CAF50) : const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF4CAF50) : Colors.white24,
          ),
        ),
        child: Text(
          '$label$arrow',
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildRarityChip(String rarity) {
    final selected = _selectedRarity == rarity;
    final color = _rarityColor(rarity);
    return GestureDetector(
      onTap: () => _onRarityTap(rarity),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.25) : const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.4),
          ),
        ),
        child: Text(
          rarity,
          style: TextStyle(
            color: selected ? color : color.withOpacity(0.6),
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCardItem(Map<String, dynamic> card) {
    final cardId = card['cardId'] ?? '';
    final name = card['name'] ?? '';
    final rarity = card['rarityCode'] ?? '';
    final number = card['collectionNumber'] ?? '';
    final latestPrice = card['latestPrice'] as num?;
    final imageUrl = resolveCardImageUrl(card);

    return GestureDetector(
      onTap: () => context.push('/card/$cardId', extra: card),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            CardImage(
              imageUrl: imageUrl,
              width: 44,
              height: 62,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rarity.isNotEmpty) ...[
                        _buildRarityBadge(rarity),
                        const SizedBox(width: 6),
                      ],
                      if (number.isNotEmpty)
                        Text(number,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            if (latestPrice != null) ...[
              const SizedBox(width: 8),
              Text(
                _formatPrice(latestPrice.toInt()),
                style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white30, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRarityBadge(String rarity) {
    final color = _rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(rarity,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 44,
      height: 62,
      color: Colors.white10,
      child: const Icon(Icons.catching_pokemon, color: Colors.white24, size: 22),
    );
  }

  String _formatPrice(int price) {
    if (price <= 0) return '0원';
    final rounded = (price / 10).round() * 10;
    final s = rounded.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$s원';
  }

  Color _rarityColor(String rarity) {
    switch (rarity) {
      case 'SSR': return const Color(0xFFFF6B6B);
      case 'SAR': return const Color(0xFFFFD700);
      case 'BWR': return const Color(0xFFE8F5E9);
      case 'CSR': return const Color(0xFF00BCD4);
      case 'CHR': return const Color(0xFF4FC3F7);
      case 'UR':  return const Color(0xFF9C27B0);
      case 'SR':  return const Color(0xFF7E57C2);
      case 'AR':  return const Color(0xFFFF9800);
      case 'MA':  return const Color(0xFFFF4081);
      case 'MUR': return const Color(0xFFE040FB);
      default:    return Colors.white54;
    }
  }
}
