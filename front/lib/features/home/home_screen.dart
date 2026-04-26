import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _myAssets = [];
  Map<String, dynamic>? _portfolio;
  Map<String, int> _marketPrices = {};
  Map<String, int> _hotPrices = {};
  List<Map<String, dynamic>> _hotCards = [];
  List<Map<String, dynamic>> _tradeSummaries = [];
  double? _coefficient;
  bool _loading = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final meRes = await ApiClient.get('/api/users/me');
      _userId = meRes['data']?['userId'] as String?;

      final futures = await Future.wait([
        if (_userId != null)
          ApiClient.get(ApiConstants.assets, params: {'userId': _userId})
        else
          Future.value({'data': []}),
        if (_userId != null)
          ApiClient.get('${ApiConstants.assets}/portfolio', params: {'userId': _userId})
        else
          Future.value({'data': null}),
        ApiClient.get('/api/cards/market', params: {
          'rarities': 'SAR,SSR,CSR',
          'page': 0,
          'size': 200,
        }),
        ApiClient.get('/api/trades/cards/summary', params: {'size': 10}),
        ApiClient.get('/api/prices/coefficient'),
      ]);

      final assets = List<Map<String, dynamic>>.from(futures[0]['data'] ?? []);

      // 카드별 평균시세 fetch
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

      int totalMarketValue = 0;
      for (final a in assets) {
        final cardId = a['cardId'] as String;
        final qty = (a['quantity'] as num?)?.toInt() ?? 1;
        totalMarketValue += (priceMap[cardId] ?? 0) * qty;
      }

      if (!mounted) return;
      setState(() {
        _myAssets = assets;
        _marketPrices = priceMap;
        _portfolio = {
          'totalCards': assets.fold<int>(0, (s, a) => s + ((a['quantity'] as num?)?.toInt() ?? 1)),
          'distinctCardCount': cardIds.length,
          'totalMarketValue': totalMarketValue,
        };

        final marketData = futures[2]['data'] as Map<String, dynamic>?;
        final all = List<Map<String, dynamic>>.from(marketData?['content'] ?? []);
        final top = all.take(30).toList()..shuffle(Random());
        _hotCards = top.take(10).toList();

        final tradesData = futures[3]['data'];
        if (tradesData is List) {
          _tradeSummaries = List<Map<String, dynamic>>.from(tradesData);
        }

        final coefData = futures[4]['data'] as Map<String, dynamic>?;
        _coefficient = (coefData?['coefficient'] as num?)?.toDouble();

        _loading = false;
      });

      // HOT 카드 한국 예상가 fetch (JP×계수, 없으면 KO 평균)
      final coef = _coefficient;
      final hotPriceMap = <String, int>{};
      await Future.wait(_hotCards.map((card) async {
        final cardId = card['cardId'] as String? ?? '';
        if (cardId.isEmpty) return;
        try {
          final res = await ApiClient.get('/api/prices/cards/$cardId/history');
          final snapshots = res['data'] as List? ?? [];

          // JP×계수 우선
          if (coef != null) {
            final jpSnaps = snapshots
                .where((s) => s['source'] == 'SCRYDEX_JP' && (s['price'] as num?) != null && (s['price'] as num) > 0)
                .toList();
            if (jpSnaps.isNotEmpty) {
              jpSnaps.sort((a, b) => (a['tradedAt'] as String).compareTo(b['tradedAt'] as String));
              final latestJp = (jpSnaps.last['price'] as num).toDouble();
              hotPriceMap[cardId] = (latestJp * coef).round();
              return;
            }
            final enSnaps = snapshots
                .where((s) => s['source'] == 'SCRYDEX_EN' && (s['price'] as num?) != null && (s['price'] as num) > 0)
                .toList();
            if (enSnaps.isNotEmpty) {
              enSnaps.sort((a, b) => (a['tradedAt'] as String).compareTo(b['tradedAt'] as String));
              final latestEn = (enSnaps.last['price'] as num).toDouble();
              hotPriceMap[cardId] = (latestEn * coef).round();
              return;
            }
          }

          // 폴백: KO APP RAW 평균
          final rawPrices = snapshots
              .where((s) => s['source'] == 'APP' && s['cardStatus'] == 'RAW'
                  && (s['price'] as num?) != null && (s['price'] as num) > 0)
              .map((s) => (s['price'] as num).toInt())
              .toList();
          if (rawPrices.isNotEmpty) {
            hotPriceMap[cardId] = (rawPrices.reduce((a, b) => a + b) / rawPrices.length).round();
          }
        } catch (_) {}
      }));

      if (mounted) setState(() => _hotPrices = hotPriceMap);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : RefreshIndicator(
              onRefresh: _loadAll,
              color: AppColors.blue,
              backgroundColor: AppColors.surface,
              child: CustomScrollView(
                slivers: [
                  _buildHeader(),
                  SliverToBoxAdapter(child: _buildMyCardsSection()),
                  SliverToBoxAdapter(child: _buildListingsSection()),
                  SliverToBoxAdapter(child: _buildHotSection()),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  SliverAppBar _buildHeader() {
    return SliverAppBar(
      backgroundColor: AppColors.bg,
      floating: true,
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.blue, Color(0xFF1A56B0)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.catching_pokemon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('포켓몬 카드',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary),
          onPressed: () {},
        ),
      ],
    );
  }

  static const _rareRarities = {'SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'UR', 'SR', 'AR', 'HR', 'ACE', 'RRR', 'RR', 'PR', 'H', 'MA', 'MUR'};

  int get _rareCardCount {
    return _myAssets.where((a) {
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

  Widget _buildMyCardsSection() {
    final totalMarketValue = (_portfolio?['totalMarketValue'] as num?)?.toInt() ?? 0;
    final totalCards = (_portfolio?['totalCards'] as num?)?.toInt() ?? 0;
    final distinctCount = (_portfolio?['distinctCardCount'] as num?)?.toInt() ?? 0;
    final showAssets = _myAssets.take(4).toList();
    final rareCount = _rareCardCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 총 평가 자산
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
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
                          AppColors.formatPrice(totalMarketValue),
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
            // 구분선
            const Divider(height: 1, color: AppColors.divider),
            // 카드 목록
            if (_myAssets.isEmpty)
              GestureDetector(
                onTap: () => context.push('/assets'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.add_circle_outline, color: AppColors.textMuted, size: 28),
                        SizedBox(height: 8),
                        Text('카드를 추가해보세요',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              ...showAssets.map((asset) => _buildMyCardRow(asset)),
              // 더보기
              if (_myAssets.length > 4)
                GestureDetector(
                  onTap: () => context.push('/assets'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
                    ),
                    child: Center(
                      child: Text(
                        '${_myAssets.length - 4}종 더보기',
                        style: const TextStyle(color: AppColors.blue, fontSize: 13),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMyCardRow(Map<String, dynamic> asset) {
    final cardId = asset['cardId'] ?? '';
    final cardData = asset['card'] as Map<String, dynamic>? ?? {};
    final name = cardData['name'] as String? ?? cardId;
    final rarity = cardData['rarityCode'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(cardData);
    final qty = (asset['quantity'] as num?)?.toInt() ?? 1;
    final marketPrice = _marketPrices[cardId];
    final totalValue = marketPrice != null ? marketPrice * qty : null;
    final glowColor = AppColors.rarityGlow(rarity);
    final hasGlow = rarity.isNotEmpty && glowColor != Colors.transparent;

    return GestureDetector(
      onTap: () => context.push('/card/$cardId', extra: {'myAsset': asset}),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            // 카드 썸네일
            Container(
              width: 38,
              height: 53,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: hasGlow ? glowColor.withOpacity(0.5) : AppColors.divider,
                  width: hasGlow ? 1.5 : 1,
                ),
                boxShadow: hasGlow
                    ? [BoxShadow(color: glowColor.withOpacity(0.25), blurRadius: 8)]
                    : null,
              ),
              child: CardImage(
                imageUrl: imageUrl,
                width: 38,
                height: 53,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 14),
            // 이름 + 등급
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (rarity.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.rarityColor(rarity).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(rarity,
                              style: TextStyle(
                                  color: AppColors.rarityColor(rarity),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text('$qty장',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            // 평가금액
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  totalValue != null ? AppColors.formatPrice(totalValue) : '-',
                  style: TextStyle(
                    color: hasGlow ? glowColor : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (marketPrice != null && qty > 1)
                  Text('개당 ${AppColors.formatPrice(marketPrice)}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 카드별 판매 요약 섹션
  Widget _buildListingsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('판매 중인 카드',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              GestureDetector(
                onTap: () => context.push('/trades'),
                child: const Text('전체보기',
                    style: TextStyle(color: AppColors.blue, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_tradeSummaries.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Column(
                children: [
                  Icon(Icons.storefront_outlined, color: AppColors.textMuted, size: 36),
                  SizedBox(height: 10),
                  Text('등록된 판매 카드가 없습니다',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            )
          else
            SizedBox(
              height: 210,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _tradeSummaries.length,
                itemBuilder: (context, index) => _buildTradeSummaryCard(_tradeSummaries[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTradeSummaryCard(Map<String, dynamic> summary) {
    final cardId = summary['cardId'] ?? '';
    final name = summary['name'] ?? '';
    final rarity = summary['rarityCode'] ?? '';
    final sellerCount = summary['sellerCount'] as num? ?? 0;
    final avgPrice = summary['avgPrice'] as num?;
    final imageUrl = resolveCardImageUrl(summary);

    final glowColor = AppColors.rarityGlow(rarity);
    final hasGlow = rarity.isNotEmpty && glowColor != Colors.transparent;

    return GestureDetector(
      onTap: () => context.push('/trades', extra: {'cardId': cardId, 'cardName': name}),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasGlow ? glowColor.withOpacity(0.55) : AppColors.divider,
            width: hasGlow ? 1.5 : 1,
          ),
          boxShadow: hasGlow
              ? [BoxShadow(color: glowColor.withOpacity(0.2), blurRadius: 10, spreadRadius: 1)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardImage(
              imageUrl: imageUrl,
              width: 140,
              height: 110,
              fit: BoxFit.cover,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (rarity.isNotEmpty)
                    Text(rarity,
                        style: TextStyle(color: AppColors.rarityColor(rarity), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  if (avgPrice != null)
                    Text(AppColors.formatPrice(avgPrice.toInt()),
                        style: TextStyle(
                            color: hasGlow ? glowColor : AppColors.green,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('$sellerCount명 판매 중',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotSection() {
    if (_hotCards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Text('HOT', style: TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold)),
                  SizedBox(width: 6),
                  Text('고등급 시세', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
              GestureDetector(
                onTap: () => context.push('/prices'),
                child: const Text('전체보기', style: TextStyle(color: AppColors.blue, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _hotCards.take(10).length,
              itemBuilder: (context, index) => _buildHotCardChip(_hotCards[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotCardRow(Map<String, dynamic> card) {
    final cardId = card['cardId'] ?? '';
    final name = card['name'] ?? '';
    final rarity = card['rarityCode'] ?? '';
    final avgPrice = _hotPrices[cardId];
    final rarityColor = AppColors.rarityColor(rarity);
    final imageUrl = resolveCardImageUrl(card);

    return GestureDetector(
      onTap: () => context.push('/card/$cardId', extra: card),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            CardImage(
              imageUrl: imageUrl,
              width: 40,
              height: 56,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (rarity.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: rarityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: rarityColor.withOpacity(0.4)),
                      ),
                      child: Text(rarity, style: TextStyle(color: rarityColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            if (avgPrice != null)
              Text(
                AppColors.formatPrice(avgPrice),
                style: const TextStyle(color: AppColors.green, fontSize: 14, fontWeight: FontWeight.bold),
              )
            else
              const Text('-', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildHotCardChip(Map<String, dynamic> card) {
    final cardId = card['cardId'] ?? '';
    final name = card['name'] ?? '';
    final rarity = card['rarityCode'] ?? '';
    final imageUrl = resolveCardImageUrl(card);
    final avgPrice = _hotPrices[cardId];
    final glowColor = AppColors.rarityGlow(rarity);
    final hasGlow = rarity.isNotEmpty && glowColor != Colors.transparent;

    return GestureDetector(
      onTap: () => context.push('/card/$cardId', extra: card),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasGlow ? glowColor.withOpacity(0.55) : AppColors.divider,
            width: hasGlow ? 1.5 : 1,
          ),
          boxShadow: hasGlow
              ? [BoxShadow(color: glowColor.withOpacity(0.2), blurRadius: 10, spreadRadius: 1)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardImage(
              imageUrl: imageUrl,
              width: 140,
              height: 110,
              fit: BoxFit.cover,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (rarity.isNotEmpty)
                    Text(rarity,
                        style: TextStyle(color: AppColors.rarityColor(rarity), fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  if (avgPrice != null)
                    Text(AppColors.formatPrice(avgPrice),
                        style: TextStyle(
                            color: hasGlow ? glowColor : AppColors.green,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
