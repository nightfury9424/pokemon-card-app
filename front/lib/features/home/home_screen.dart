import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter, lerpDouble;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/notifiers/asset_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/rarity.dart';
import '../../core/utils/price_label.dart';
import '../../core/utils/price_display_policy.dart';
import '../../core/widgets/animated_counter.dart';
import '../../core/widgets/card_image.dart' show CardImage, resolveCardImageUrl;
import '../../core/widgets/pressable.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 연속 reload race 방지용 시퀀스 토큰. 매 _loadAll 시작 시 +1, 응답 시 현재 토큰과 비교.
  int _loadSeq = 0;
  List<Map<String, dynamic>> _myAssets = [];
  Map<String, dynamic>? _portfolio;
  List<Map<String, dynamic>> _topCards = [];
  List<Map<String, dynamic>> _hotCards = [];
  List<Map<String, dynamic>> _topGainerCards = [];
  List<Map<String, dynamic>> _recentTrades = [];
  late final PageController _carouselController;
  late final PageController _marketCarouselController;
  /// 캐러셀 자동 회전 타이머 (items >= 2일 때 3초 간격).
  Timer? _autoAdvanceTimer;
  static const int _kCarouselStart = 500000;
  static const int _kCarouselVirtual = 1000000;
  int _carouselPage = _kCarouselStart;
  int _marketCarouselPage = _kCarouselStart;
  int _carouselTab = 0;    // 0 = 내 카드, 1 = 시장 랭킹
  int _marketSubTab = 0;   // 0 = 시세 높은순, 1 = 관심 많은

  bool _loading = true;
  String? _userId;


  // 레어도 hierarchy는 AppRarity로 통일 (한국 포카 시세 기준)
  // REFACTOR_2026-05-12.md 4차 디자인 시스템.
  static int _rarityRank(String r) => AppRarity.rank(r);

  // ignore: unused_element
  Map<String, dynamic>? get _topRarityAsset {
    if (_myAssets.isEmpty) return null;
    Map<String, dynamic>? best;
    var bestRank = 99;
    for (final asset in _myAssets) {
      final rarity = (asset['card']?['rarityCode'] as String?) ?? '';
      final rank = _rarityRank(rarity);
      if (best == null || rank < bestRank) {
        best = asset;
        bestRank = rank;
      }
    }
    return best;
  }

  @override
  void initState() {
    super.initState();
    // viewportFraction 줄여서 양옆 카드가 더 가까이 (현재카드↔다음카드 사이 여백 ↓)
    _carouselController = PageController(viewportFraction: 0.6, initialPage: _kCarouselStart);
    _marketCarouselController = PageController(viewportFraction: 0.6, initialPage: _kCarouselStart);
    AssetNotifier.instance.addListener(_onExternalChange);
    _loadAll();
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    AssetNotifier.instance.removeListener(_onExternalChange);
    _carouselController.dispose();
    _marketCarouselController.dispose();
    super.dispose();
  }

  /// 3초마다 활성 캐러셀의 다음 페이지로. 사용자가 드래그 중이거나
  /// items < 2면 skip. 무한 캐러셀(items >= 3)은 끝없이, finite(2장)은 wrap.
  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final isMyCards = _carouselTab == 0;
      final items = isMyCards ? _myCardCarouselItems() : _marketCarouselItems();
      if (items.length < 2) return;

      final controller = isMyCards ? _carouselController : _marketCarouselController;
      if (!controller.hasClients) return;
      // 사용자가 드래그/관성 스크롤 중이면 skip
      final pos = controller.position;
      if (pos.isScrollingNotifier.value) return;

      final currentPage = controller.page?.round() ?? 0;
      int nextPage;
      if (items.length >= 3) {
        nextPage = currentPage + 1; // 무한 PageView
      } else {
        // 2장 finite: 끝 도달 시 처음으로
        nextPage = (currentPage + 1) % items.length;
      }
      controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onExternalChange() {
    if (mounted) _loadData();
  }

  Future<void> _openCardItem(Map<String, dynamic> item) async {
    final cardId = item['cardId'] as String? ?? '';
    if (cardId.isEmpty) return;
    final extra = item['asset'] != null ? {'myAsset': item['asset']} : item['card'];
    final changed = await context.push<bool>('/card/$cardId', extra: extra);
    if (changed == true && mounted) _loadData();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!mounted) return;
    final seq = ++_loadSeq;
    if (!silent) setState(() => _loading = true);

    try {
      final meRes = await ApiClient.get('/api/users/me');
      _userId = meRes['data']?['userId'] as String?;
    } catch (_) {}

    Map<String, dynamic>? assetRes, topRes, hotRes, tradeRes, portfolioRes;
    List<Map<String, dynamic>> topGainerCards = [];
    await Future.wait([
      () async {
        try {
          assetRes = _userId != null
              ? await ApiClient.get(
                  ApiConstants.assets,
                  params: {'userId': _userId},
                )
              : {'data': []};
        } catch (_) {
          assetRes = {'data': []};
        }
      }(),
      () async {
        try {
          if (_userId != null) {
            portfolioRes = await ApiClient.get(
              '${ApiConstants.assets}/portfolio',
              params: {'userId': _userId},
            );
          }
        } catch (_) {}
      }(),
      () async {
        try {
          topRes = await ApiClient.get(
            '/api/cards/market',
            params: {
              'rarities': 'SSR,SAR,CSR,CHR,UR,BWR',
              'sortBy': 'price',
              'sortDir': 'desc',
              'page': 0,
              'size': 6,
            },
          );
        } catch (_) {}
      }(),
      () async {
        try {
          hotRes = await ApiClient.get(
            '/api/cards/market',
            params: {
              'rarities': 'SSR,SAR,CSR,CHR,UR,BWR',
              'sortBy': 'rarity',
              'sortDir': 'asc',
              'page': 0,
              'size': 6,
            },
          );
        } catch (_) {}
      }(),
      () async {
        try {
          tradeRes = await ApiClient.get(
            '/api/trades/cards/summary',
            params: {'size': 6},
          );
        } catch (_) {}
      }(),
      () async {
        try {
          // 3차-C: 별도 Dio 인스턴스 제거 → ApiClient 통일 (토큰 + 401/5xx 인터셉터 적용)
          final list = await ApiClient.getList(
            '/api/cards/market/top-gainers',
            params: {'size': 10},
          );
          topGainerCards = list
              .whereType<Map>()
              .map((card) => Map<String, dynamic>.from(card))
              .toList();
        } catch (_) {}
      }(),
    ]);

    final assets = List<Map<String, dynamic>>.from(assetRes?['data'] ?? []);

    final topData = topRes?['data'] as Map<String, dynamic>?;
    final topCards = List<Map<String, dynamic>>.from(topData?['content'] ?? []);
    final hotData = hotRes?['data'] as Map<String, dynamic>?;
    final hotRaw = List<Map<String, dynamic>>.from(hotData?['content'] ?? []);
    hotRaw.shuffle(Random());
    final hotCards = hotRaw.take(6).toList();

    final trades =
        (tradeRes?['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (!mounted) return;
    // 더 최신 load가 시작됐다면 stale 응답이므로 무시 (필드 오염 방지를 위해 모든 대입 전에 체크).
    if (seq != _loadSeq) return;
    setState(() {
      _myAssets = assets;
      _topCards = topCards;
      _hotCards = hotCards;
      _topGainerCards = topGainerCards;
      _recentTrades = trades;
      _portfolio = portfolioRes?['data'] as Map<String, dynamic>?;
      _loading = false;
    });
  }

  Future<void> _loadData() => _loadAll(silent: true);

  int get _totalCards => _myAssets.fold<int>(
    0,
    (s, a) => s + ((a['quantity'] as num?)?.toInt() ?? 1),
  );

  static const _highRarities = {'SSR', 'SAR', 'BWR', 'CSR', 'CHR', 'UR'};
  int get _highRareCount => _myAssets
      .where((a) {
        final r = (a['card']?['rarityCode'] as String?) ?? '';
        return _highRarities.contains(r);
      })
      .fold(0, (s, a) => s + ((a['quantity'] as num?)?.toInt() ?? 1));

  int? _assetDisplayPrice(Map<String, dynamic> asset) =>
      (asset['displayPrice'] as num?)?.toInt();

  int _assetMarketValue(Map<String, dynamic> asset) {
    final price = _assetDisplayPrice(asset) ?? 0;
    final qty = (asset['quantity'] as num?)?.toInt() ?? 1;
    return price * qty;
  }

  int get _totalValue {
    if (_myAssets.isNotEmpty) {
      return _myAssets.fold<int>(0, (s, a) => s + _assetMarketValue(a));
    }
    return (_portfolio?['totalMarketValue'] as num?)?.toInt() ?? 0;
  }

  double get _totalPurchaseValue => _myAssets.fold<double>(
    0,
    (s, a) {
      final qty = (a['quantity'] as num?)?.toInt() ?? 1;
      return s + (((a['purchasePrice'] as num?)?.toDouble() ?? 0) * qty);
    },
  );

  double get _portfolioMarketValue => _totalValue.toDouble();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.blue,
                strokeWidth: 2,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAll,
              color: AppColors.blue,
              backgroundColor: AppColors.surface,
              child: CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  // 4차-Round4-3: 카드 컬렉션 앱 — 시각적 임팩트(카드)가 위, 포트폴리오는 그 다음
                  // 1) 카드 랭킹 캐러셀 (금액/인기/수익률 3 서브탭)
                  SliverToBoxAdapter(child: _buildCarousel()),
                  // 2) 내 자산 (포트폴리오 hero)
                  if (_userId != null)
                    SliverToBoxAdapter(child: _buildHeroSection()),
                  const SliverToBoxAdapter(child: SizedBox(height: 48)),
                ],
              ),
            ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.bg,
      floating: true,
      snap: true,
      pinned: false,
      elevation: 0,
      centerTitle: true,
      titleSpacing: 20,
      title: RichText(
        text: const TextSpan(
          children: [
            TextSpan(
              text: 'Poke',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            TextSpan(
              text: 'Folio',
              style: TextStyle(
                color: AppColors.blue,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _NotificationBell(),
        ),
      ],
    );
  }


  // ignore: unused_element
  Widget _buildAssetSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        onTap: () => context.go('/assets'),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            border: Border.all(color: AppColors.divider, width: 1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.blue.withValues(alpha: 0.15),
                  AppColors.surfaceCard.withValues(alpha: 0.0),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '내 자산',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.push('/assets'),
                      child: Row(
                        children: const [
                          Text(
                            '전체 보기',
                            style: TextStyle(
                              color: AppColors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.blue,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  AppColors.formatPrice(_totalValue),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    height: 1.1,
                  ),
                ),
                Builder(
                  builder: (context) {
                    final purchase = _totalPurchaseValue;
                    final market = _portfolioMarketValue;
                    if (purchase <= 0 || market <= 0) {
                      return const SizedBox(height: 4);
                    }
                    final diff = market - purchase;
                    final rate = diff / purchase * 100;
                    final isPos = rate >= 0;
                    final sign = isPos ? '+' : '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '$sign${AppColors.formatPrice(diff.toInt())} ($sign${rate.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          // 색상 정책 (feedback_color_policy.md): 양=빨강, 음=파랑.
                          color: isPos ? AppColors.red : AppColors.blue,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _AssetStat(label: '보유', value: '$_totalCards종'),
                    const SizedBox(width: 20),
                    _AssetStat(label: '고레어', value: '$_highRareCount장'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    final purchase = _totalPurchaseValue;
    final market = _portfolioMarketValue;
    final hasProfit = purchase > 0 && market > 0;
    final diff = market - purchase;
    final rate = purchase > 0 ? diff / purchase * 100 : 0.0;
    final isPositive = diff >= 0;
    final sign = isPositive ? '+' : '-';

    final heroCard = _topRarityAsset?['card'] as Map<String, dynamic>?;
    final heroImageUrl = heroCard != null ? resolveCardImageUrl(heroCard) : null;

    // 4차-Round4-2: 풀 리디자인 — 글래스 layer + ShaderMask gradient text + 정교한 multi-layer
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Pressable(
        onTap: () => context.push('/assets'),
        pressedScale: 0.98,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Container(
            height: 144,
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: [
                BoxShadow(
                  color: AppColors.blue.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1) 카드 이미지 더 강한 blur (sigma 18)
                if (heroImageUrl != null)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: CardImage(
                      imageUrl: heroImageUrl,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                // 2) 메인 그라데이션 (좌상 = 액센트 / 우하 = 어두움)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [0.0, 0.5, 1.0],
                      colors: [
                        AppColors.blue.withValues(alpha: 0.28),
                        AppColors.surfaceCard.withValues(alpha: 0.78),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
                // 3) 글래스 inner border (subtle)
                Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.xl - 1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                      width: 1,
                    ),
                  ),
                ),
                // 4) 우상단 액센트 글로우 (radial)
                Positioned(
                  top: -40,
                  right: -40,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.blue.withValues(alpha: 0.25),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // 5) 텍스트 콘텐츠
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '내 자산',
                            style: AppText.label.copyWith(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '자산 보기',
                                style: AppText.caption.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 큰 숫자 — 단순 흰색 + shadow로 가독성 우선
                          TweenedCounter(
                            value: _totalValue,
                            formatter: (v) => AppColors.formatPrice(v.toInt()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              letterSpacing: -1.4,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (hasProfit)
                            Text(
                              '$sign${AppColors.formatPrice(diff.abs().toInt())} ($sign${rate.abs().toStringAsFixed(1)}%)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // 색상 정책 (feedback_color_policy.md): 양=빨강, 음=파랑.
                                color: isPositive ? AppColors.red : AppColors.blue,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            )
                          else
                            const SizedBox(height: 18),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Icon(
                              Icons.style_rounded,
                              color: Colors.white70,
                              size: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '보유 카드 $_totalCards장',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _myCardCarouselItems() {
    if (_myAssets.isEmpty) {
      return _topGainerCards.take(10).map((card) {
        final price = (card['koEstimatedPrice'] as num?)?.toInt() ??
            (card['latestPrice'] as num?)?.toInt();
        final pct = (card['gainPct'] as num?)?.toDouble();
        return {
          'card': card,
          'cardId': card['cardId'] as String? ?? '',
          'price': price,
          'changePct': pct,
          'changeLabel': '전일 대비',
        };
      }).toList();
    }
    final sorted = [..._myAssets]
      ..sort((a, b) {
        return _assetMarketValue(b).compareTo(_assetMarketValue(a));
      });
    return sorted.take(10).map((asset) {
      final card = asset['card'] as Map<String, dynamic>? ?? {};
      final cardId = (asset['cardId'] as String?) ?? (card['cardId'] as String?) ?? '';
      // 내 카드: 등록 시점(구매가) 대비. 구매가 없으면 표시 안 함.
      final marketPrice = _assetDisplayPrice(asset);
      final purchasePrice = (asset['purchasePrice'] as num?)?.toInt();
      double? pct;
      String? label;
      if (marketPrice != null && purchasePrice != null && purchasePrice > 0) {
        pct = (marketPrice - purchasePrice) * 100.0 / purchasePrice;
        label = '등록 시점 대비';
      }
      return {
        'card': card,
        'asset': asset,
        'cardId': cardId,
        'price': marketPrice,
        'changePct': pct,
        'changeLabel': label,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _marketCarouselItems() {
    // 4차-Round4-3: 홈 단순화 — 시장 랭킹 3 서브탭 (금액/인기/수익률)
    final source = switch (_marketSubTab) {
      0 => _topCards,        // 금액
      1 => _hotCards,        // 인기
      2 => _topGainerCards,  // 수익률
      _ => _topCards,
    };
    return source.map((card) {
      final price = (card['koEstimatedPrice'] as num?)?.toInt() ??
          (card['latestPrice'] as num?)?.toInt();
      final cardId = card['cardId'] as String? ?? '';
      final pct = (card['gainPct'] as num?)?.toDouble();
      return {
        'card': card,
        'cardId': cardId,
        'price': price,
        'changePct': pct,
        'changeLabel': pct != null ? '전일 대비' : null,
      };
    }).toList();
  }

  Widget _buildCarousel() {
    // 카드 좀 더 크게 (0.40 → 0.46, max 460)
    final height = (MediaQuery.of(context).size.height * 0.46).clamp(380.0, 460.0);
    final isMyCards = _carouselTab == 0;
    final items = isMyCards ? _myCardCarouselItems() : _marketCarouselItems();
    final controller = isMyCards ? _carouselController : _marketCarouselController;
    final currentPage = isMyCards ? _carouselPage : _marketCarouselPage;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 탭 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _CarouselTab(
                  label: _myAssets.isNotEmpty ? '내 카드' : '오늘의 TOP',
                  selected: _carouselTab == 0,
                  onTap: () => setState(() { _carouselTab = 0; }),
                ),
                const SizedBox(width: 8),
                _CarouselTab(
                  label: '시장 랭킹',
                  selected: _carouselTab == 1,
                  onTap: () => setState(() { _carouselTab = 1; }),
                ),
                if (_carouselTab == 1) ...[
                  const Spacer(),
                  _MiniSegment(
                    labels: const ['금액', '인기', '수익률'],
                    selected: _marketSubTab,
                    onChanged: (i) {
                      final newItems = switch (i) {
                        0 => _topCards,
                        1 => _hotCards,
                        2 => _topGainerCards,
                        _ => _topCards,
                      };
                      final len = newItems.isEmpty ? 1 : newItems.length;
                      final aligned = _kCarouselStart - (_kCarouselStart % len);
                      setState(() { _marketSubTab = i; _marketCarouselPage = aligned; });
                      if (_marketCarouselController.hasClients) {
                        _marketCarouselController.jumpToPage(aligned);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // items 수가 3 미만이면 controller가 가질 수 있는 page를 itemCount-1로 clamp.
          // 이전 상태에서 _kCarouselStart로 초기화된 page가 itemCount=1,2에 invalid라 page indicator/peek 깨짐 방지.
          // controller + state 모두 0으로 reset해야 dots/현재 page 표시도 일관성 유지.
          // items.isEmpty면 maxValid=-1이 되어 무한 jumpToPage loop가 생길 수 있어 가드.
          Builder(builder: (_) {
            if (items.isNotEmpty && items.length < 3 && controller.hasClients) {
              final maxValid = items.length - 1;
              if (controller.page != null && controller.page! > maxValid) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (controller.hasClients) controller.jumpToPage(0);
                  setState(() {
                    if (isMyCards) {
                      _carouselPage = 0;
                    } else {
                      _marketCarouselPage = 0;
                    }
                  });
                });
              }
            }
            return const SizedBox.shrink();
          }),
          if (items.isEmpty)
            SizedBox(
              height: height,
              child: const Center(
                child: Text('데이터 없음', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            )
          else if (items.length == 1)
            // 1장: 캐러셀 없이 가운데 단일 카드. peek/repeat 방지.
            SizedBox(
              height: height + 16,
              child: Center(
                child: FractionallySizedBox(
                  widthFactor: 0.6,
                  child: _CarouselCard(
                    item: items[0],
                    distFromCenter: 0,
                    isLeftOfCenter: false,
                    onTap: () => _openCardItem(items[0]),
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: height + 16,
              child: PageView.builder(
                clipBehavior: Clip.none,
                controller: controller,
                // 3장 이상이면 무한 캐러셀(양옆 peek). 2장은 finite(왼쪽 없음, 오른쪽 peek).
                itemCount: items.length >= 3 ? _kCarouselVirtual : items.length,
                onPageChanged: (page) => setState(() {
                  if (isMyCards) { _carouselPage = page; }
                  else { _marketCarouselPage = page; }
                }),
                itemBuilder: (context, index) {
                  final realIndex = items.length >= 3 ? index % items.length : index;
                  return AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      double page = currentPage.toDouble();
                      if (controller.hasClients && controller.position.haveDimensions) {
                        page = controller.page ?? page;
                      }
                      final dist = (page - index).abs().clamp(0.0, 1.0);
                      return _CarouselCard(
                        item: items[realIndex],
                        distFromCenter: dist,
                        isLeftOfCenter: page > index,
                        onTap: () => _openCardItem(items[realIndex]),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            _CarouselDots(
              count: items.length,
              currentIndex: currentPage % items.length,
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMyCardsPreview() {
    final sortedAssets = [..._myAssets]
      ..sort((a, b) {
        return _assetMarketValue(b).compareTo(_assetMarketValue(a));
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 0, 0),
      child: SizedBox(
        height: 160,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: sortedAssets.length,
          padding: const EdgeInsets.only(right: 16),
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final asset = sortedAssets[index];
            final card = asset['card'] as Map<String, dynamic>? ?? {};
            final cardId = asset['cardId'] as String? ?? '';
            final name = card['name'] as String? ?? cardId;
            final rarity = card['rarityCode'] as String? ?? '';
            final price = _assetDisplayPrice(asset);
            final imageUrl = resolveCardImageUrl(card);

            return GestureDetector(
              onTap: () async {
                final changed = await context.push<bool>(
                  '/card/$cardId',
                  extra: {'myAsset': asset},
                );
                if (changed == true && mounted) _loadData();
              },
              child: SizedBox(
                width: 90,
                height: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      height: 126,
                      child: CardImage(
                        imageUrl: imageUrl,
                        width: 90,
                        height: 126,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rarity.isNotEmpty ? rarity : '-',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          price != null ? AppColors.formatPrice(price) : '-',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 4차-Round4-3: 사용자 의향으로 build 호출 제거. 데이터/함수는 롤백 대비 보존.
  // ignore: unused_element
  Widget _buildRecentTrades() {
    if (_recentTrades.isEmpty) return const SizedBox.shrink();
    final visibleTrades = _recentTrades.take(4).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionTitle('판매 중인 카드'),
              GestureDetector(
                onTap: () => context.go('/trade-list'),
                child: const Text(
                  '거래 탭에서 더보기',
                  style: TextStyle(
                    color: AppColors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: visibleTrades.asMap().entries.map((entry) {
                final index = entry.key;
                final trade = entry.value;
                return Column(
                  children: [
                    _TradeCompactRow(
                      trade: trade,
                      onTap: () async {
                        final cardId = trade['cardId'] as String? ?? '';
                        final cardName = trade['name'] as String? ?? '';
                        await context.push(
                          '/trades',
                          extra: {'cardId': cardId, 'cardName': cardName},
                        );
                      },
                    ),
                    if (index < visibleTrades.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.divider,
                        indent: 72,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 알림 종 아이콘 + unread badge. 클릭 시 알림 list 모달.
class _NotificationBell extends StatefulWidget {
  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final res = await ApiClient.get('/api/notifications/me/unread-count');
      final c = (res['data']?['count'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _unreadCount = c);
    } catch (_) {}
  }

  Future<void> _showNotifications() async {
    await showModalBottomSheet(
      context: context,
      // ShellRoute child(/home) 안에서 호출되어 MainShell FAB가 시트를 가리는 문제 방지.
      useRootNavigator: true,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotificationSheet(),
    );
    _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showNotifications,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.notifications_none_rounded, color: Colors.white, size: 22),
          ),
          if (_unreadCount > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationSheet extends StatefulWidget {
  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.get('/api/notifications/me');
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ApiClient.post('/api/notifications/me/read-all', {});
      _load();
    } catch (_) {}
  }

  String _relativeTime(String iso) {
    try {
      final t = DateTime.parse(iso);
      final diff = DateTime.now().difference(t);
      if (diff.inMinutes < 1) return '방금 전';
      if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
      if (diff.inHours < 24) return '${diff.inHours}시간 전';
      if (diff.inDays < 7) return '${diff.inDays}일 전';
      return '${t.month}/${t.day}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      builder: (_, controller) => Column(
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              children: [
                const Text('알림', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (_items.any((i) => i['isRead'] == false))
                  TextButton(
                    onPressed: _markAllRead,
                    child: const Text('모두 읽음', style: TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2))
                : _items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('아직 알림이 없습니다',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.dividerSoft),
                        itemBuilder: (ctx, i) {
                          final n = _items[i];
                          final isRead = n['isRead'] == true;
                          final type = n['type'] as String? ?? '';
                          final icon = type == 'TRADE_ON_MY_BUY_ORDER'
                              ? Icons.local_offer_rounded
                              : Icons.shopping_cart_outlined;
                          final accent = type == 'TRADE_ON_MY_BUY_ORDER'
                              ? AppColors.blue
                              : AppColors.green;
                          return InkWell(
                            onTap: () async {
                              final cardId = (n['linkCardId'] as String?) ?? '';
                              await ApiClient.post(
                                  '/api/notifications/${n['notificationId']}/read', {});
                              if (cardId.isNotEmpty && context.mounted) {
                                Navigator.pop(context);
                                context.push('/card/$cardId');
                              } else {
                                _load();
                              }
                            },
                            child: Container(
                              color: isRead
                                  ? Colors.transparent
                                  : AppColors.blue.withValues(alpha: 0.04),
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(icon, color: accent, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n['title'] as String? ?? '',
                                          style: TextStyle(
                                            color: isRead ? AppColors.textSecondary : Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if ((n['body'] as String? ?? '').isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            n['body'] as String,
                                            style: TextStyle(
                                              color: isRead ? AppColors.textMuted : AppColors.textSecondary,
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          _relativeTime(n['createdAt'] as String? ?? ''),
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isRead)
                                    Container(
                                      width: 8, height: 8,
                                      margin: const EdgeInsets.only(top: 6, left: 6),
                                      decoration: const BoxDecoration(
                                        color: AppColors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _CarouselTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CarouselTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textMuted,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MiniSegment extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const _MiniSegment({required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: labels.asMap().entries.map((e) {
          final sel = e.key == selected;
          return GestureDetector(
            onTap: () => onChanged(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? AppColors.blue : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  color: sel ? Colors.white : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CarouselCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final double distFromCenter;
  final bool isLeftOfCenter;

  const _CarouselCard({
    required this.item,
    required this.onTap,
    required this.distFromCenter,
    required this.isLeftOfCenter,
  });

  @override
  State<_CarouselCard> createState() => _CarouselCardState();
}

class _CarouselCardState extends State<_CarouselCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.item['card'] as Map<String, dynamic>? ?? {};
    final cardId = widget.item['cardId'] as String? ?? '';
    final name = card['name'] as String? ?? cardId;
    final rarity = card['rarityCode'] as String? ?? '';
    final price = widget.item['price'] as int?;
    final imageUrl = resolveCardImageUrl(card);
    final centerFactor = (1 - widget.distFromCenter).clamp(0.0, 1.0);
    final scale = lerpDouble(0.88, 1.0, centerFactor)!;
    final opacity = lerpDouble(0.65, 1.0, centerFactor)!;
    final amplitude = 8 * centerFactor;
    final sign = widget.isLeftOfCenter ? -1.0 : 1.0;

    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        final floatingY = Tween<double>(begin: 0, end: -amplitude).transform(
          Curves.easeInOut.transform(_floatController.value),
        );
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..translateByDouble(0.0, floatingY, 0.0, 1.0)
          ..scaleByDouble(scale, scale, scale, 1.0)
          ..rotateY(-sign * widget.distFromCenter * 0.18);

        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 100 / 140,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.blue.withValues(
                          alpha: 0.45 * centerFactor,
                        ),
                        blurRadius: 28 * (1 - widget.distFromCenter * 0.8),
                        spreadRadius: 2 * centerFactor,
                        offset: Offset(0, 10 * centerFactor),
                      ),
                    ],
                  ),
                  child: CardImage(
                    imageUrl: imageUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            // 1행: [rarity pill] [국내 예상가/해외 참고가 pill] — 가격 기준 명확화 (2026-05-28 라벨 정리).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.rarityColor(
                      rarity,
                    ).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.rarityColor(
                        rarity,
                      ).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    rarity.isNotEmpty ? rarity : '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.rarityColor(rarity),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if ((card['language'] as String? ?? 'KO') == 'KO') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.divider, width: 0.5),
                    ),
                    child: Text(
                      PriceLabel.resolve(
                        labelType: card['koPriceLabelType'] as String?,
                        price: price,
                      ),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // 2행: 가격 — 더 굵고 크게 (라벨과 줄 분리로 신뢰 정보 시각 우선순위 ↑).
            Text(
              price != null ? AppColors.formatPrice(price) : '시세 준비중',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: price != null
                    ? AppColors.textPrimary
                    : AppColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            // 변동률 (등록 시점 대비 / 전일 대비)
            // PriceDisplayPolicy (2026-05-16): 저가 카드 % 숨김/Stage B 전체 숨김/Stage C 변동 적음
            // home API에는 prevPrice가 없어서 currentPrice + pct로 역산 후 정책 판단
            if (widget.item['changePct'] != null) ...[
              const SizedBox(height: 4),
              Builder(builder: (_) {
                final pct = (widget.item['changePct'] as num).toDouble();
                final label = widget.item['changeLabel'] as String? ?? '전일 대비';
                final price = (widget.item['price'] as num?)?.toInt();
                int? prevPriceApprox;
                if (price != null && pct > -100) {
                  prevPriceApprox = (price / (1 + pct / 100)).round();
                }
                final display = PriceDisplayPolicy.buildChangeDisplay(
                  lastPrice: price,
                  prevPrice: prevPriceApprox,
                  prefix: label,
                );
                if (display == null) return const SizedBox.shrink();
                final color = switch (display.color) {
                  // 색상 정책 (feedback_color_policy.md): 양=빨강, 음=파랑.
                  PriceChangeColor.positive => AppColors.red,
                  PriceChangeColor.negative => AppColors.blue,
                  PriceChangeColor.neutral => AppColors.textMuted,
                };
                return Text(
                  display.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _CarouselDots extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _CarouselDots({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final visibleCount = min(count, 5);
    final start = count <= 5
        ? 0
        : (currentIndex - 2).clamp(0, count - visibleCount).toInt();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(visibleCount, (visibleIndex) {
        final index = start + visibleIndex;
        final selected = index == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: selected ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: selected ? AppColors.blue : AppColors.divider,
            borderRadius: BorderRadius.circular(6),
          ),
        );
      }),
    );
  }
}

class _AssetStat extends StatelessWidget {
  final String label;
  final String value;

  const _AssetStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _TradeCompactRow extends StatelessWidget {
  final Map<String, dynamic> trade;
  final VoidCallback onTap;

  const _TradeCompactRow({required this.trade, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cardName = trade['name'] as String? ?? '';
    final rarity = trade['rarityCode'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(trade);
    final avgPrice = (trade['avgPrice'] as num?)?.toInt();
    final sellerCount = (trade['sellerCount'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CardImage(
              imageUrl: imageUrl,
              width: 40,
              height: 56,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cardName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    rarity.isNotEmpty ? rarity : '레어도 미정',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  avgPrice != null ? AppColors.formatPrice(avgPrice) : '-',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '판매자 $sellerCount명',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
