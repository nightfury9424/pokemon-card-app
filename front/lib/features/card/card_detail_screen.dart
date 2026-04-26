import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/widgets/card_image.dart';
import '../../core/theme/app_colors.dart';
import 'models/card_model.dart';

class CardDetailScreen extends StatefulWidget {
  final String cardId;
  final Map<String, dynamic>? cardData;
  final Map<String, dynamic>? myAsset;

  const CardDetailScreen({super.key, required this.cardId, this.cardData, this.myAsset});

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  List<PriceSnapshotModel> _prices = [];
  bool _loadingPrices = true;
  bool _loadingChart  = true;
  Map<String, dynamic>? _cardDetail;
  List<Map<String, dynamic>> _listings = [];
  List<Map<String, dynamic>> _globalPrices = [];
  double? _coefficient;
  double? _exchangeRate;
  String _selectedMarket = 'KO'; // KO / EN / JP
  String _selectedGrade  = 'RAW'; // RAW / PSA10 / PSA9
  Map<String, dynamic>? _scrydexLive;
  Map<String, dynamic>? _enHistory;
  Map<String, dynamic>? _jpHistory;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiClient.get('${ApiConstants.cards}/${widget.cardId}'),
        ApiClient.get('${ApiConstants.prices}/${widget.cardId}/history'),
        ApiClient.get('/api/trades', params: {'cardId': widget.cardId, 'page': 0, 'size': 20}),
        ApiClient.get('${ApiConstants.prices}/${widget.cardId}/global-history'),
        ApiClient.get('/api/prices/coefficient'),
      ]);
      if (!mounted) return;
      final items = results[1]['data'] as List? ?? [];
      final tradesData = results[2]['data'];
      final globalItems = results[3]['data'] as List? ?? [];
      final coefficientData = results[4]['data'] as Map<String, dynamic>?;
      setState(() {
        _cardDetail = results[0]['data'] as Map<String, dynamic>?;
        _prices = items.map((e) => PriceSnapshotModel.fromJson(e)).toList();
        if (tradesData is Map) {
          _listings = List<Map<String, dynamic>>.from(tradesData['content'] ?? []);
        }
        _globalPrices = List<Map<String, dynamic>>.from(globalItems);
        _coefficient = (coefficientData?['coefficient'] as num?)?.toDouble();
        _exchangeRate = (coefficientData?['exchangeRate'] as num?)?.toDouble();
        _loadingPrices = false;
      });
      _loadScrydexData();
    } catch (e) {
      if (mounted) setState(() => _loadingPrices = false);
    }
  }

  Future<void> _loadScrydexData() async {
    try {
      final results = await Future.wait([
        ApiClient.get('${ApiConstants.prices}/${widget.cardId}/scrydex-live'),
        ApiClient.get('${ApiConstants.prices}/${widget.cardId}/scrydex-history', params: {'source': 'EN'}),
        ApiClient.get('${ApiConstants.prices}/${widget.cardId}/scrydex-history', params: {'source': 'JP'}),
      ]);
      if (!mounted) return;
      setState(() {
        final live = results[0]['data'] as Map<String, dynamic>?;
        final en   = results[1]['data'] as Map<String, dynamic>?;
        final jp   = results[2]['data'] as Map<String, dynamic>?;
        if (live != null) _scrydexLive = live;
        if (en   != null) _enHistory   = en;
        if (jp   != null) _jpHistory   = jp;
        _loadingChart = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingChart = false);
    }
  }

  // 사용 안 함 (히스토리는 scrydex에서 직접 가져옴)


  @override
  Widget build(BuildContext context) {
    final data = _cardDetail ?? widget.cardData;
    final name = data?['name'] ?? '';
    final rarity = data?['rarityCode'] ?? '';
    final number = data?['collectionNumber'] ?? '';
    final productName = data?['productName'] as String?;
    final seriesName = data?['seriesName'] as String?;
    final productType = data?['productType'] as String?;
    final imageUrl = resolveCardImageUrl(data);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: Colors.white,
        title: Text(name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, widget.myAsset != null ? 80 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCardHero(name, rarity, number, productName, seriesName, productType, imageUrl, data),
            const SizedBox(height: 20),
            _buildPriceSection(),
            const SizedBox(height: 16),
            _buildListingsSection(name, rarity),
          ],
        ),
      ),
      bottomNavigationBar: widget.myAsset != null ? _buildSellBar(name, rarity, imageUrl) : null,
    );
  }

  // ─────────────────────────────────────────────
  // 카드 히어로: 이름 → 큰 이미지 → 부가정보
  // ─────────────────────────────────────────────

  Widget _buildCardHero(String name, String rarity, String number,
      String? productName, String? seriesName, String? productType,
      String? imageUrl, Map<String, dynamic>? data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 카드 이름
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),

          // 카드 이미지 (크게)
          CardImage(
            imageUrl: imageUrl,
            width: 220,
            height: 308,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(height: 14),

          // 등급 뱃지 + 번호
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (rarity.isNotEmpty) ...[
                _buildBadge(rarity),
                const SizedBox(width: 8),
              ],
              if (number.isNotEmpty)
                Text(number, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),

          // 세트 정보
          if (productName != null || seriesName != null) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                final productId = _cardDetail?['productId'] as String?;
                if (productId != null) {
                  context.push('/product/$productId', extra: {
                    'productName': productName,
                    'seriesName': seriesName,
                  });
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (productName != null) ..._buildProductNameLines(productName),
                        if (seriesName != null)
                          Text(seriesName,
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      if (productType != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(_productTypeLabel(productType),
                              style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 한국 예상 가치 + 해외 시세 차트
  // ─────────────────────────────────────────────

  Widget _buildPriceSection() {
    final hist = _selectedMarket == 'JP' ? _jpHistory : _enHistory;
    final exRate = _exchangeRate ?? 1400.0;
    final coef   = _coefficient  ?? 1.0;

    // 현재가 요약 (scrydexLive 또는 히스토리 마지막 값)
    final rawNmPts  = hist?['rawNm']  as List?;
    final psa10Pts  = hist?['psa10']  as List?;
    final psa9Pts   = hist?['psa9']   as List?;

    double? lastRaw  = _lastPrice(rawNmPts);
    double? lastPsa10 = _lastPrice(psa10Pts);
    double? lastPsa9  = _lastPrice(psa9Pts);

    // KO 탭: KO 예상가 (RAW NM × 환율 × 계수)
    final enRaw = _lastPrice(_enHistory?['rawNm'] as List?);
    final koEstimated = enRaw != null ? (enRaw * exRate * coef).round() : null;

    final hasData = hist != null || koEstimated != null;

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
          // 탭 헤더
          Row(
            children: [
              const Text('시세 차트',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.3)),
              const Spacer(),
              _buildMarketTabs(),
            ],
          ),
          const SizedBox(height: 12),

          if (_loadingPrices || _loadingChart)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.white30, strokeWidth: 2),
                    SizedBox(height: 10),
                    Text('시세 불러오는 중...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            )
          else if (!hasData && hist == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('시세 데이터 없음', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            )
          else ...[
            // 현재가 요약 칩들
            if (_selectedMarket == 'KO') ...[
              if (koEstimated != null) ...[
                Text(_formatPrice(koEstimated),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
                const SizedBox(height: 4),
                const Text('해외 RAW × 환율 × 시장계수',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ] else ...[
              // EN/JP 탭: RAW / PSA10 / PSA9 현재가 칩 (탭하면 차트 전환)
              if (lastRaw != null || lastPsa10 != null || lastPsa9 != null)
                Row(children: [
                  if (lastRaw != null) Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedGrade = 'RAW'),
                      child: _buildPriceChip('RAW NM', lastRaw, '\$', const Color(0xFF2196F3), selected: _selectedGrade == 'RAW'),
                    ),
                  ),
                  if (lastRaw != null && lastPsa10 != null) const SizedBox(width: 8),
                  if (lastPsa10 != null) Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedGrade = 'PSA10'),
                      child: _buildPriceChip('PSA 10', lastPsa10, '\$', const Color(0xFFFFD700), selected: _selectedGrade == 'PSA10'),
                    ),
                  ),
                  if (lastPsa10 != null && lastPsa9 != null) const SizedBox(width: 8),
                  if (lastPsa9 != null) Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedGrade = 'PSA9'),
                      child: _buildPriceChip('PSA 9', lastPsa9, '\$', const Color(0xFF90CAF9), selected: _selectedGrade == 'PSA9'),
                    ),
                  ),
                ]),
            ],
            const SizedBox(height: 16),

            // 차트
            _buildMarketChart(hist, exRate, coef),
            const SizedBox(height: 10),
            _buildMarketLegend(hist),
          ],
        ],
      ),
    );
  }

  double? _lastPrice(List? pts) {
    if (pts == null) return null;
    for (final p in pts.reversed) {
      final price = (p['price'] as num?)?.toDouble();
      if (price != null) return price;
    }
    return null;
  }

  Widget _buildPriceChip(String label, double price, String prefix, Color color, {bool selected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(selected ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(selected ? 0.75 : 0.3), width: selected ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text('$prefix${price.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildMarketTabs() {
    return Row(
      children: ['KO', 'EN', 'JP'].map((market) {
        final selected = _selectedMarket == market;
        return GestureDetector(
          onTap: () => setState(() { _selectedMarket = market; _selectedGrade = 'RAW'; }),
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? AppColors.blue : Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(market,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                )),
          ),
        );
      }).toList(),
    );
  }

  List<FlSpot> _ptsToSpots(List? pts, DateTime start, {double scale = 1.0}) {
    if (pts == null) return [];
    // 날짜 오름차순 정렬
    final sorted = List<dynamic>.from(pts)
      ..sort((a, b) {
        final da = DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(0);
        return da.compareTo(db);
      });
    final spots = <FlSpot>[];
    for (final p in sorted) {
      final date  = p['date']  as String?;
      final price = (p['price'] as num?)?.toDouble();
      if (date == null || price == null) continue; // null gap 스킵
      final dt = DateTime.tryParse(date);
      if (dt == null) continue;
      final x = dt.difference(start).inDays.toDouble();
      if (x < 0) continue; // start 이전 데이터 제외
      spots.add(FlSpot(x, price * scale));
    }
    return spots;
  }

  // 여러 pts 목록에서 가장 이른 날짜 추출
  DateTime _earliestDate(List<List?> ptsList) {
    DateTime? earliest;
    for (final pts in ptsList) {
      if (pts == null) continue;
      for (final p in pts) {
        final d = DateTime.tryParse(p['date'] as String? ?? '');
        if (d != null && (earliest == null || d.isBefore(earliest))) earliest = d;
      }
    }
    return earliest ?? DateTime.now().subtract(const Duration(days: 30));
  }

  Widget _buildMarketChart(Map<String, dynamic>? hist, double exRate, double coef) {
    final rawPts   = hist?['rawNm'] as List?;
    final psa10Pts = hist?['psa10'] as List?;
    final psa9Pts  = hist?['psa9']  as List?;

    // 모든 라인의 가장 이른 날짜로 start 통일 (음수 X 방지)
    final DateTime start;
    if (_selectedMarket == 'KO') {
      final enRawPts = _enHistory?['rawNm'] as List?;
      start = _earliestDate([enRawPts]);
    } else {
      start = _earliestDate([rawPts, psa10Pts, psa9Pts]);
    }
    final totalDays = DateTime.now().difference(start).inDays.toDouble();

    // 표시할 단일 라인 결정
    final List<FlSpot> activeSpots;
    final Color activeColor;
    final bool isKrw = _selectedMarket == 'KO';

    if (isKrw) {
      final enRaw = _enHistory?['rawNm'] as List?;
      activeSpots = _ptsToSpots(enRaw, start, scale: exRate * coef);
      activeColor = const Color(0xFF4CAF50);
    } else {
      final activePts = _selectedGrade == 'PSA10' ? psa10Pts
          : _selectedGrade == 'PSA9'  ? psa9Pts
          : rawPts;
      activeSpots = _ptsToSpots(activePts, start);
      activeColor = _selectedGrade == 'PSA10' ? const Color(0xFFFFD700)
          : _selectedGrade == 'PSA9'  ? const Color(0xFF90CAF9)
          : const Color(0xFF2196F3);
    }

    final allY = activeSpots.map((s) => s.y).toList();
    if (allY.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('데이터 없음', style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    final minY = (allY.reduce((a, b) => a < b ? a : b) * 0.88).clamp(0.0, double.infinity);
    final maxY =  allY.reduce((a, b) => a > b ? a : b) * 1.12;
    final yStep = (maxY - minY) / 2;

    if (activeSpots.length < 2) return const SizedBox.shrink();

    final bar = LineChartBarData(
      spots: activeSpots,
      isCurved: false,
      color: activeColor,
      barWidth: 1.8,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [activeColor.withOpacity(0.22), activeColor.withOpacity(0.0)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
    );

    final xInterval = (totalDays / 4).ceilToDouble().clamp(1.0, double.infinity);

    return SizedBox(
      height: 220,
      child: LineChart(LineChartData(
        minY: minY, maxY: maxY,
        minX: 0, maxX: totalDays > 0 ? totalDays : 1,
        clipData: const FlClipData.all(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1A2035),
            tooltipRoundedRadius: 10,
            tooltipBorder: const BorderSide(color: Colors.white12),
            getTooltipItems: (spots) => spots.map((s) {
              final val = isKrw
                  ? _formatPrice(s.y.toInt())
                  : '\$${s.y.toStringAsFixed(2)}';
              return LineTooltipItem(val,
                  TextStyle(color: activeColor, fontSize: 11, fontWeight: FontWeight.w600));
            }).toList(),
          ),
        ),
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          horizontalInterval: yStep > 0 ? yStep : null,
          getDrawingHorizontalLine: (_) => const FlLine(color: Colors.white10, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 62,
            interval: yStep > 0 ? yStep : null,
            getTitlesWidget: (v, m) {
              if (v == m.min || v == m.max) return const SizedBox.shrink();
              final label = isKrw ? _formatPrice(v.toInt()) : '\$${v.toStringAsFixed(0)}';
              return Padding(padding: const EdgeInsets.only(left: 6),
                  child: Text(label, style: const TextStyle(color: Colors.white30, fontSize: 9)));
            },
          )),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 24, interval: xInterval,
            getTitlesWidget: (v, m) {
              if (v == m.min || v == m.max) return const SizedBox.shrink();
              final dt = start.add(Duration(days: v.toInt()));
              return Text('${dt.month}/${dt.day}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10));
            },
          )),
        ),
        lineBarsData: [bar],
      )),
    );
  }

  Widget _buildMarketLegend(Map<String, dynamic>? hist) {
    if (_selectedMarket != 'KO') return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 18, height: 2, color: const Color(0xFF4CAF50)),
      const SizedBox(width: 5),
      const Text('KO 예상가', style: TextStyle(color: Colors.white54, fontSize: 11)),
    ]);
  }

  // ─────────────────────────────────────────────
  // scrydex 실시간 가격 (RAW / PSA 9 / PSA 10)
  // ─────────────────────────────────────────────

  Widget _buildScrydexSection() {
    final live = _scrydexLive;
    if (live == null) return const SizedBox.shrink();

    final rawNm = (live['rawNm'] as num?)?.toDouble();
    final psa10 = (live['psa10'] as num?)?.toDouble();
    final psa9  = (live['psa9']  as num?)?.toDouble();
    final source = live['source'] as String? ?? 'EN';

    if (rawNm == null && psa10 == null && psa9 == null) return const SizedBox.shrink();

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
              const Text('해외 등급 시세',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('scrydex · $source',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (rawNm != null)
                Expanded(child: _buildGradeCell('RAW', 'Near Mint', rawNm, const Color(0xFF4CAF50))),
              if (psa10 != null) ...[
                if (rawNm != null) const SizedBox(width: 10),
                Expanded(child: _buildGradeCell('PSA 10', '최신 판매가', psa10, const Color(0xFFFFD700))),
              ],
              if (psa9 != null) ...[
                if (rawNm != null || psa10 != null) const SizedBox(width: 10),
                Expanded(child: _buildGradeCell('PSA 9', '최신 판매가', psa9, const Color(0xFF90CAF9))),
              ],
            ],
          ),
          const SizedBox(height: 8),
          const Text('USD 기준 · eBay 최신 판매가',
              style: TextStyle(color: Colors.white24, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildGradeCell(String grade, String label, double usd, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(grade,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('\$${usd.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
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
          const Text('이 카드 판매 중',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_listings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('판매 중인 카드가 없습니다',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
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
                onTap: () => context.push('/trades/$tradeId'),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.blue.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    cardStatus == 'GRADED' && gradingCompany != null
                                        ? '$gradingCompany ${gradeValue ?? ''}'
                                        : 'RAW',
                                    style: const TextStyle(
                                        color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(seller['nickname'] ?? '',
                                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt,
                              style: const TextStyle(color: Colors.white30, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (price != null)
                            Text(_formatPrice(price.toInt()),
                                style: const TextStyle(
                                    color: Color(0xFF4CAF50), fontSize: 14, fontWeight: FontWeight.bold))
                          else
                            const Text('가격 협의',
                                style: TextStyle(color: Colors.white38, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
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
  // 판매하기 바
  // ─────────────────────────────────────────────

  Widget _buildSellBar(String cardName, String rarity, String? imageUrl) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: GestureDetector(
        onTap: () async {
          final created = await context.push<bool>(
            '/trades/create',
            extra: {'cardId': widget.cardId, 'cardName': cardName, 'rarity': rarity, 'imageUrl': imageUrl},
          );
          if (created == true && mounted) _loadData();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.blue, Color(0xFF1A56B0)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sell_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('이 카드 판매하기',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Util
  // ─────────────────────────────────────────────

  List<Widget> _buildProductNameLines(String productName) {
    final idx = productName.indexOf('「');
    if (idx > 0) {
      return [
        Text(productName.substring(0, idx).trim(),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Text(productName.substring(idx),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ];
    }
    return [
      Text(productName, softWrap: true,
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
    ];
  }

  String _productTypeLabel(String type) {
    switch (type) {
      case 'BOOSTER': return '부스터팩';
      case 'DECK': return '덱';
      case 'PROMO': return '프로모';
      case 'SPECIAL': return '특별판';
      default: return type;
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
      child: Text(rarity,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Color _rarityColor(String rarity) {
    switch (rarity) {
      case 'SAR': case 'SSR': return const Color(0xFFFFD700);
      case 'BWR': return const Color(0xFFE8F5E9);
      case 'CSR': case 'CHR': return const Color(0xFF00BCD4);
      case 'SR': case 'UR': return const Color(0xFF9C27B0);
      default: return Colors.white54;
    }
  }

  String _formatPrice(int price) {
    if (price <= 0) return '0원';
    final rounded = (price / 10).round() * 10;
    final formatter = rounded.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '${formatter}원';
  }
}
