import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class AssetScreen extends StatefulWidget {
  const AssetScreen({super.key});

  @override
  State<AssetScreen> createState() => _AssetScreenState();
}

enum _SortMode { rarity, price, name, quantity }

class _AssetScreenState extends State<AssetScreen> {
  List<Map<String, dynamic>> _assets = [];
  Map<String, dynamic>? _portfolio;
  Map<String, int> _marketPrices = {}; // cardId → 평균시세
  bool _loading = true;
  String? _userId;

  _SortMode _sortMode = _SortMode.rarity;
  bool _sortAscending = true;

  static const _rarityOrder = {
    'SSR': 0, 'SAR': 1, 'BWR': 2, 'CSR': 3, 'CHR': 4, 'UR': 5, 'SR': 6, 'AR': 7,
    'HR': 8, 'ACE': 9, 'RRR': 10, 'RR': 11, 'PR': 12, 'H': 13,
  };

  void _applySortInPlace() {
    final asc = _sortAscending ? 1 : -1;
    switch (_sortMode) {
      case _SortMode.rarity:
        _assets.sort((a, b) {
          final ra = _rarityOrder[(a['card']?['rarityCode'] as String?) ?? ''] ?? 99;
          final rb = _rarityOrder[(b['card']?['rarityCode'] as String?) ?? ''] ?? 99;
          if (ra != rb) return ra.compareTo(rb) * asc;
          return ((a['card']?['name'] as String?) ?? '').compareTo((b['card']?['name'] as String?) ?? '');
        });
      case _SortMode.price:
        _assets.sort((a, b) {
          final pa = (a['purchasePrice'] as num?)?.toInt();
          final pb = (b['purchasePrice'] as num?)?.toInt();
          if (pa == null && pb == null) return 0;
          if (pa == null) return 1;
          if (pb == null) return -1;
          return pa.compareTo(pb) * asc;
        });
      case _SortMode.name:
        _assets.sort((a, b) =>
            ((a['card']?['name'] as String?) ?? '').compareTo((b['card']?['name'] as String?) ?? '') * asc);
      case _SortMode.quantity:
        _assets.sort((a, b) {
          final qa = (a['quantity'] as num?)?.toInt() ?? 1;
          final qb = (b['quantity'] as num?)?.toInt() ?? 1;
          return qa.compareTo(qb) * asc;
        });
    }
  }

  void _onSortTap(_SortMode mode) {
    setState(() {
      if (_sortMode == mode) {
        _sortAscending = !_sortAscending;
      } else {
        _sortMode = mode;
        // 가격순은 기본 내림차순 (비싼 것 먼저)
        _sortAscending = mode == _SortMode.price ? false : true;
      }
      _applySortInPlace();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final meRes = await ApiClient.get('/api/users/me');
      _userId = meRes['data']['userId'] as String?;
      if (_userId == null) return;

      final assetRes = await ApiClient.get(ApiConstants.assets, params: {'userId': _userId});
      final assets = List<Map<String, dynamic>>.from(assetRes['data'] ?? []);

      // 카드별 평균시세 fetch (history 스냅샷에서 RAW 평균 계산)
      final priceMap = <String, int>{};
      final cardIds = assets.map((a) => a['cardId'] as String).toSet();
      await Future.wait(cardIds.map((cardId) async {
        try {
          final res = await ApiClient.get('/api/prices/cards/$cardId/history');
          final snapshots = res['data'] as List? ?? [];
          final rawPrices = snapshots
              .where((s) => s['cardStatus'] == 'RAW' && (s['price'] as num?) != null && (s['price'] as num) > 0)
              .map((s) => (s['price'] as num).toInt())
              .toList();
          if (rawPrices.isNotEmpty) {
            priceMap[cardId] = (rawPrices.reduce((a, b) => a + b) / rawPrices.length).round();
          }
        } catch (_) {}
      }));

      // 총 자산 = 시세 × 수량 합산
      int totalMarketValue = 0;
      for (final a in assets) {
        final cardId = a['cardId'] as String;
        final qty = (a['quantity'] as num?)?.toInt() ?? 1;
        final price = priceMap[cardId] ?? 0;
        totalMarketValue += price * qty;
      }

      if (!mounted) return;
      setState(() {
        _assets = assets;
        _marketPrices = priceMap;
        _portfolio = {
          'totalCards': assets.fold<int>(0, (s, a) => s + ((a['quantity'] as num?)?.toInt() ?? 1)),
          'distinctCardCount': cardIds.length,
          'totalMarketValue': totalMarketValue,
        };
        _loading = false;
        _applySortInPlace();
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAsset(String assetId) async {
    try {
      await ApiClient.delete('${ApiConstants.assets}/$assetId');
      setState(() => _assets.removeWhere((a) => a['assetId'] == assetId));
      _loadPortfolio();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 실패')),
        );
      }
    }
  }

  Future<void> _loadPortfolio() async {
    if (_userId == null) return;
    try {
      final res = await ApiClient.get('${ApiConstants.assets}/portfolio', params: {'userId': _userId});
      if (mounted) setState(() => _portfolio = res['data'] as Map<String, dynamic>?);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: Colors.white,
        title: const Text('내 자산'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddOptions,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white30))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildPortfolioSummary()),
                  SliverToBoxAdapter(child: _buildSortRow()),
                  if (_assets.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text('보유 카드가 없습니다\n우상단 + 버튼으로 카드를 추가하세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 15)),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.62,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildAssetGridItem(_assets[index]),
                          childCount: _assets.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  static const _rareRarities = {'SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'UR', 'SR', 'AR', 'HR', 'ACE', 'RRR', 'RR', 'PR', 'H', 'MA', 'MUR'};

  int get _rareCardCount {
    return _assets.where((a) {
      final rarity = (a['card']?['rarityCode'] as String?) ?? '';
      return _rareRarities.contains(rarity);
    }).fold(0, (sum, a) => sum + ((a['quantity'] as num?)?.toInt() ?? 1));
  }

  Map<String, dynamic> _getBadgeTier(int count) {
    if (count == 0) {
      return {'name': '뱃지 잠김', 'img': null, 'color': AppColors.textMuted, 'locked': true};
    } else if (count <= 200) {
      return {'name': '몬스터볼', 'img': 'assets/balls/monster_ball.webp', 'color': const Color(0xFFE53935), 'locked': false};
    } else if (count <= 600) {
      return {'name': '슈퍼볼', 'img': 'assets/balls/super_ball.webp', 'color': AppColors.blue, 'locked': false};
    } else if (count <= 1500) {
      return {'name': '하이퍼볼', 'img': 'assets/balls/hyper_ball.webp', 'color': const Color(0xFF9C27B0), 'locked': false};
    } else {
      return {'name': '마스터볼', 'img': 'assets/balls/master_ball.webp', 'color': AppColors.gold, 'locked': false};
    }
  }

  Widget _buildBadge(int rareCount) {
    final tier = _getBadgeTier(rareCount);
    final color = tier['color'] as Color;
    final locked = tier['locked'] as bool;
    final name = tier['name'] as String;
    final img = tier['img'] as String?;

    return GestureDetector(
      onTap: locked
          ? () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('고레어 카드를 1장 이상 등록하면 뱃지가 열립니다!'),
                  duration: Duration(seconds: 2),
                ),
              )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textMuted),
            )
          else
            Image.asset(img!, width: 44, height: 44),
          const SizedBox(height: 5),
          Text(
            locked ? '뱃지 잠김' : '등급 : $name',
            style: TextStyle(
              color: locked ? AppColors.textMuted : color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioSummary() {
    final totalCards = _portfolio?['totalCards'] ?? 0;
    final totalMarketValue = _portfolio?['totalMarketValue'] ?? 0;
    final distinctCount = _portfolio?['distinctCardCount'] ?? 0;
    final rareCount = _rareCardCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('총 평가 자산',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.2)),
                  const SizedBox(height: 6),
                  Text(
                    _formatPrice(totalMarketValue),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$totalCards장 보유 · $distinctCount종',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            _buildBadge(rareCount),
          ],
        ),
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
          Center(child: _buildSortChip('등급순', _SortMode.rarity)),
          const SizedBox(width: 6),
          Center(child: _buildSortChip('가격순', _SortMode.price)),
          const SizedBox(width: 6),
          Center(child: _buildSortChip('이름순', _SortMode.name)),
          const SizedBox(width: 6),
          Center(child: _buildSortChip('수량순', _SortMode.quantity)),
        ],
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
          color: selected ? AppColors.green : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.green : Colors.white24,
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

  Widget _buildAssetGridItem(Map<String, dynamic> asset) {
    final cardId = asset['cardId'] ?? '';
    final quantity = asset['quantity'] ?? 1;
    final marketPrice = _marketPrices[cardId];
    final cardStatus = asset['cardStatus'] ?? 'RAW';
    final assetId = asset['assetId'] ?? '';
    final cardData = asset['card'] as Map<String, dynamic>? ?? {};
    final cardName = cardData['name'] as String? ?? cardId;
    final rarity = cardData['rarityCode'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(cardData);

    return GestureDetector(
      onTap: () => context.push('/card/$cardId', extra: {'myAsset': asset}),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CardImage(
                    imageUrl: imageUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _confirmDelete(assetId),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white70, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cardName,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (rarity.isNotEmpty)
                    Text(rarity,
                        style: TextStyle(color: AppColors.rarityColor(rarity), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildChip(cardStatus == 'GRADED' ? '그레이딩' : 'RAW',
                          cardStatus == 'GRADED' ? AppColors.gold : AppColors.blue),
                      Text('$quantity장', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    marketPrice != null ? _formatPrice(marketPrice) : '시세 없음',
                    style: TextStyle(
                      color: marketPrice != null ? AppColors.textPrimary : AppColors.textMuted,
                      fontSize: 12, fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('자산 추가', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildOptionTile(
                icon: Icons.qr_code_scanner,
                label: '스캔으로 추가',
                sub: '카드를 카메라로 스캔해서 추가',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/scanner');
                },
              ),
              const SizedBox(height: 10),
              _buildOptionTile(
                icon: Icons.search,
                label: '직접 검색',
                sub: '카드 이름으로 검색해서 추가',
                onTap: () {
                  Navigator.pop(context);
                  _showCardSearch();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({required IconData icon, required String label, required String sub, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.blue, size: 28),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _showCardSearch() {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> search(String query) async {
            if (query.trim().length < 2) return;
            setModalState(() => searching = true);
            try {
              final res = await ApiClient.get('/api/cards/search', params: {'name': query});
              final list = res['data'] as List? ?? [];
              setModalState(() {
                results = list.map((e) => e as Map<String, dynamic>).toList();
                searching = false;
              });
            } catch (_) {
              setModalState(() => searching = false);
            }
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '카드 이름 검색 (2글자 이상)',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward, color: AppColors.blue),
                          onPressed: () => search(searchCtrl.text),
                        ),
                      ),
                      onSubmitted: search,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (searching)
                    const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: Colors.white30))
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollCtrl,
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final card = results[i];
                          final cardId = card['cardId'] ?? '';
                          final name = card['name'] ?? '';
                          final rarity = card['rarityCode'] ?? '';
                          final cardImgUrl = resolveCardImageUrl(card);
                          return ListTile(
                            leading: CardImage(
                              imageUrl: cardImgUrl,
                              width: 36,
                              height: 50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            title: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                            subtitle: rarity.isNotEmpty
                                ? Text(rarity, style: TextStyle(color: AppColors.rarityColor(rarity), fontSize: 11, fontWeight: FontWeight.bold))
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              _showAssetForm(cardId, name, rarity, resolveCardImageUrl(card));
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAssetForm(String cardId, String cardName, String rarity, [String? imageUrl]) {
    final memoCtrl = TextEditingController();
    int quantity = 1;
    String cardStatus = 'RAW';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CardImage(
                    imageUrl: imageUrl,
                    width: 44,
                    height: 62,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cardName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                      if (rarity.isNotEmpty)
                        Text(rarity, style: TextStyle(color: AppColors.rarityColor(rarity), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 수량
              Row(
                children: [
                  const Text('수량', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: AppColors.textSecondary),
                    onPressed: () { if (quantity > 1) setModalState(() => quantity--); },
                  ),
                  Text('$quantity', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.blue),
                    onPressed: () => setModalState(() => quantity++),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 상태
              Row(
                children: [
                  const Text('상태', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => setModalState(() => cardStatus = 'RAW'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: cardStatus == 'RAW' ? AppColors.blue.withOpacity(0.2) : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cardStatus == 'RAW' ? AppColors.blue : AppColors.divider),
                      ),
                      child: Text('RAW', style: TextStyle(color: cardStatus == 'RAW' ? AppColors.blue : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setModalState(() => cardStatus = 'GRADED'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: cardStatus == 'GRADED' ? AppColors.gold.withOpacity(0.2) : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cardStatus == 'GRADED' ? AppColors.gold : AppColors.divider),
                      ),
                      child: Text('그레이딩', style: TextStyle(color: cardStatus == 'GRADED' ? AppColors.gold : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 메모
              TextField(
                controller: memoCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '메모 (선택)',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _submitAsset(
                    cardId: cardId,
                    quantity: quantity,
                    cardStatus: cardStatus,
                    memo: memoCtrl.text.trim(),
                  );
                },
                child: const Text('자산 추가', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitAsset({
    required String cardId,
    required int quantity,
    required String cardStatus,
    String? memo,
  }) async {
    if (_userId == null) return;
    try {
      await ApiClient.post(ApiConstants.assets, {
        'data': {
          'userId': _userId,
          'cardId': cardId,
          'quantity': quantity,
          'cardStatus': cardStatus,
          if (memo != null && memo.isNotEmpty) 'memo': memo,
          'purchasedAt': DateTime.now().toIso8601String().substring(0, 10),
        }
      });
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('자산에 추가됐습니다'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('추가 실패'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(String assetId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('자산 삭제', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('이 카드를 자산에서 삭제할까요?', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        ],
      ),
    );
    if (ok == true) _deleteAsset(assetId);
  }

  Widget _buildAssetItem(Map<String, dynamic> asset) {
    final cardId = asset['cardId'] ?? '';
    final quantity = asset['quantity'] ?? 1;
    final purchasePrice = asset['purchasePrice'];
    final cardStatus = asset['cardStatus'] ?? 'RAW';
    final memo = asset['memo'] ?? '';
    final assetId = asset['assetId'] ?? '';
    final cardData = asset['card'] as Map<String, dynamic>? ?? {};
    final cardName = cardData['name'] as String? ?? cardId;
    final rarity = cardData['rarityCode'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(cardData);

    return Dismissible(
      key: Key(assetId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade800,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _deleteAsset(assetId),
      child: GestureDetector(
        onTap: () => context.push('/card/$cardId', extra: {'myAsset': asset}),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              CardImage(
                imageUrl: imageUrl,
                width: 52,
                height: 72,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cardName,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (rarity.isNotEmpty)
                      Text(rarity, style: TextStyle(color: AppColors.rarityColor(rarity), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildChip(cardStatus == 'GRADED' ? '그레이딩' : 'RAW',
                            cardStatus == 'GRADED' ? AppColors.gold : AppColors.blue),
                        const SizedBox(width: 6),
                        Text('$quantity장', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                    if (memo.isNotEmpty)
                      Text(memo, style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (purchasePrice != null)
                    Text(_formatPrice(purchasePrice),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '-';
    final p = ((price as num).toInt() / 10).round() * 10;
    if (p <= 0) return '0원';
    final s = p.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$s원';
  }
}
