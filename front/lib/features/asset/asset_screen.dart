import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/notifiers/asset_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/rarity.dart';
import '../../core/widgets/animated_counter.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/card_image.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/rarity_aura.dart';

class AssetScreen extends StatefulWidget {
  final int initialTabIndex;
  const AssetScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AssetScreen> createState() => _AssetScreenState();
}

enum _SortMode { rarity, price, name, quantity }

class _AssetScreenState extends State<AssetScreen> {
  /// 연속 reload race 방지용 시퀀스 토큰.
  int _loadSeq = 0;
  List<Map<String, dynamic>> _assets = [];
  Map<String, dynamic>? _portfolio;
  // 4차-Round4-4 Phase 5: 내 매수 주문 sub-tab
  List<Map<String, dynamic>> _myBuyOrders = [];
  bool _loading = true;
  String? _userId;
  late int _tabIndex = widget.initialTabIndex; // 0=전체 1=판매중 2=내 매수

  _SortMode _sortMode = _SortMode.rarity;
  bool _sortAscending = true;

  List<Map<String, dynamic>> get _filteredAssets => _tabIndex == 1
      ? _assets.where((a) => a['isSelling'] == true).toList()
      : _assets;

  // 레어도 hierarchy는 AppRarity로 통일 — 한국 포카 시세 기준 (MUR > SSR > SAR > PR > ...)
  // REFACTOR_2026-05-12.md 4차 디자인 시스템.

  // 카드 격자 테두리 — 시그너처 레어도는 색 + 글로우
  static const _premiumRarities = {'MUR', 'UR', 'SAR', 'AR', 'MA', 'BWR', 'SSR'};
  bool _isRarityPremium(String r) => _premiumRarities.contains(r);
  Color _rarityBorderColor(String r) => _isRarityPremium(r)
      ? AppColors.rarityGlow(r).withValues(alpha: 0.45)
      : AppColors.divider;

  void _applySortInPlace() {
    final asc = _sortAscending ? 1 : -1;
    switch (_sortMode) {
      case _SortMode.rarity:
        _assets.sort((a, b) {
          final ra = AppRarity.rank((a['card']?['rarityCode'] as String?));
          final rb = AppRarity.rank((b['card']?['rarityCode'] as String?));
          if (ra != rb) return ra.compareTo(rb) * asc;
          return ((a['card']?['name'] as String?) ?? '').compareTo(
            (b['card']?['name'] as String?) ?? '',
          );
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
        _assets.sort(
          (a, b) =>
              ((a['card']?['name'] as String?) ?? '').compareTo(
                (b['card']?['name'] as String?) ?? '',
              ) *
              asc,
        );
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
    AssetNotifier.instance.addListener(_onExternalChange);
    _loadData();
    if (widget.initialTabIndex == 2) {
      _loadMyBuyOrders();
    }
  }

  @override
  void didUpdateWidget(covariant AssetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      setState(() => _tabIndex = widget.initialTabIndex);
      if (widget.initialTabIndex == 2 && _myBuyOrders.isEmpty) {
        _loadMyBuyOrders();
      }
    }
  }

  @override
  void dispose() {
    AssetNotifier.instance.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    final seq = ++_loadSeq;
    try {
      final meRes = await ApiClient.get('/api/users/me');
      _userId = meRes['data']['userId'] as String?;
      if (_userId == null) return;

      final assetRes = await ApiClient.get(
        ApiConstants.assets,
        params: {'userId': _userId},
      );
      final assets = List<Map<String, dynamic>>.from(assetRes['data'] ?? []);

      // 자산 응답의 displayPrice(asset.language별 환산가)를 그대로 합산.
      int totalMarketValue = 0;
      for (final a in assets) {
        final dp = (a['displayPrice'] as num?)?.toInt();
        final qty = (a['quantity'] as num?)?.toInt() ?? 1;
        if (dp != null && dp > 0) totalMarketValue += dp * qty;
      }
      final cardIds = assets.map((a) => a['cardId'] as String).toSet();

      if (!mounted) return;
      // 더 최신 load가 시작됐다면 stale 응답이므로 무시.
      if (seq != _loadSeq) return;
      setState(() {
        _assets = assets;
        _portfolio = {
          'totalCards': assets.fold<int>(
            0,
            (s, a) => s + ((a['quantity'] as num?)?.toInt() ?? 1),
          ),
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
      AssetNotifier.instance.notifyChanged();
      if (!mounted) return;
      setState(() {
        _assets.removeWhere((a) => a['assetId'] == assetId);
        // 포트폴리오 로컬 재계산 (totalMarketValue 유지)
        final newTotal = _assets.fold<int>(
          0,
          (s, a) => s + ((a['quantity'] as num?)?.toInt() ?? 1),
        );
        final newDistinct = _assets
            .map((a) => a['cardId'] as String)
            .toSet()
            .length;
        int newMarketValue = 0;
        for (final a in _assets) {
          final qty = (a['quantity'] as num?)?.toInt() ?? 1;
          final dp = (a['displayPrice'] as num?)?.toInt() ?? 0;
          newMarketValue += dp * qty;
        }
        _portfolio = {
          'totalCards': newTotal,
          'distinctCardCount': newDistinct,
          'totalMarketValue': newMarketValue,
        };
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('삭제 실패')));
      }
    }
  }

  // ignore: unused_element
  Future<void> _startSelling(Map<String, dynamic> asset) async {
    final assetId = asset['assetId'] as String? ?? '';
    if (assetId.isEmpty) return;

    final cardStatus = asset['cardStatus'] as String? ?? 'RAW';
    final estimatedGrade = (asset['estimatedGrade'] as num?)?.toDouble();
    final cardData =
        (asset['card'] is Map
            ? Map<String, dynamic>.from(asset['card'] as Map)
            : null) ??
        {};
    final cardId = asset['cardId'] as String? ?? '';
    final cardName = cardData['name'] as String? ?? cardId;

    if (cardStatus == 'GRADED') {
      await _showGradedSellSheet(asset);
      return;
    }

    if (estimatedGrade == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('판매 전 앱 등급 분석이 필요합니다')));
      final graded = await context.push<bool>(
        '/grading/capture',
        extra: {'assetId': assetId, 'cardId': cardId, 'cardName': cardName},
      );
      if (graded == true && mounted) {
        _loadData();
      }
      return;
    }

    await _showRawSellPriceSheet(asset, cardName, estimatedGrade);
  }

  Future<void> _showRawSellPriceSheet(
    Map<String, dynamic> asset,
    String cardName,
    double estimatedGrade,
  ) async {
    final assetId = asset['assetId'] as String? ?? '';
    final priceCtrl = TextEditingController();
    bool submitting = false;
    bool created = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> submit() async {
            final price = int.tryParse(
              priceCtrl.text.trim().replaceAll(',', ''),
            );
            if (price == null || price <= 0) return;
            setModal(() => submitting = true);
            try {
              final res = await ApiClient.post('/api/trades/from-asset', {
                'data': {'assetId': assetId, 'price': price},
              });
              final data = res['data'];
              final tradeId = (data is Map ? data['tradeId'] : null) as String?;
              if (!mounted || !ctx.mounted) return;
              created = true;
              Navigator.pop(ctx);
              setState(() {
                asset['isSelling'] = true;
                asset['activeTradeId'] = tradeId;
              });
            } catch (_) {
              setModal(() => submitting = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('판매 등록 실패'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '판매가 입력',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$cardName  ·  앱 분석 ${estimatedGrade.toStringAsFixed(1)}점',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: '판매가 입력 (원)',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    suffixText: '원',
                    suffixStyle: const TextStyle(
                      color: AppColors.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '취소',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: submitting ? null : submit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.blue, Color(0xFF1A56B0)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            submitting ? '등록 중...' : '판매 등록',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (created && mounted) _loadData();
  }

  // ignore: unused_element
  Future<void> _stopSelling(Map<String, dynamic> asset) async {
    final tradeId = asset['activeTradeId'] as String?;
    if (tradeId == null || tradeId.isEmpty) return;
    try {
      await ApiClient.delete('/api/trades/$tradeId');
      if (!mounted) return;
      setState(() {
        asset['isSelling'] = false;
        asset['activeTradeId'] = null;
      });
      if (mounted) _loadData();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('판매 내리기 실패'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showGradedSellSheet(Map<String, dynamic> asset) async {
    final assetId = asset['assetId'] as String? ?? '';
    if (assetId.isEmpty) return;

    final priceCtrl = TextEditingController();
    final picker = ImagePicker();
    String? gradingCompany = asset['gradingCompany'] as String?;
    String? gradeValue = asset['gradeValue'] as String?;
    File? slabPhoto;
    bool submitting = false;
    bool created = false;

    const gradingCompanies = ['PSA', 'BRG'];
    const gradeValues = ['10', '9.5', '9', '8.5', '8', '7.5', '7', '6', '5'];

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surfaceCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModal) {
            final price = int.tryParse(priceCtrl.text.trim());
            final canSubmit =
                gradingCompany != null &&
                gradeValue != null &&
                slabPhoto != null &&
                price != null &&
                price > 0 &&
                !submitting;

            Future<void> pickSlabPhoto() async {
              final picked = await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 90,
                maxWidth: 1200,
              );
              if (picked == null) return;
              setModal(() => slabPhoto = File(picked.path));
            }

            Future<void> submit() async {
              if (!canSubmit) return;
              setModal(() => submitting = true);
              try {
                await ApiClient.patch(
                  '${ApiConstants.assets}/$assetId/grading-info',
                  data: {
                    'gradingCompany': gradingCompany,
                    'gradeValue': gradeValue,
                  },
                );
                await ApiClient.uploadFile(
                  '${ApiConstants.assets}/$assetId/slab-image',
                  slabPhoto!.path,
                  field: 'slab_image',
                );
                final res = await ApiClient.post('/api/trades/from-asset', {
                  'data': {'assetId': assetId, 'price': price},
                });
                final tradeId =
                    (res['data'] as Map<String, dynamic>?)?['tradeId']
                        as String?;
                if (!mounted || !ctx.mounted) return;
                created = true;
                Navigator.pop(ctx);
                setState(() {
                  asset['gradingCompany'] = gradingCompany;
                  asset['gradeValue'] = gradeValue;
                  asset['isSelling'] = true;
                  asset['activeTradeId'] = tradeId;
                });
              } catch (_) {
                setModal(() => submitting = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('판매 등록 실패'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 16),
                    const Text(
                      '등급 카드 판매 등록',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '감정사',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: gradingCompanies.map((company) {
                        final selected = gradingCompany == company;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(company),
                            selected: selected,
                            selectedColor: AppColors.gold.withValues(
                              alpha: 0.2,
                            ),
                            backgroundColor: AppColors.surfaceElevated,
                            labelStyle: TextStyle(
                              color: selected
                                  ? AppColors.gold
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                            side: BorderSide(
                              color: selected
                                  ? AppColors.gold
                                  : AppColors.divider,
                            ),
                            onSelected: (_) =>
                                setModal(() => gradingCompany = company),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: gradeValues.contains(gradeValue)
                          ? gradeValue
                          : null,
                      dropdownColor: AppColors.surfaceCard,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: '등급',
                        labelStyle: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.divider,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.divider,
                          ),
                        ),
                      ),
                      items: gradeValues
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => setModal(() => gradeValue = v),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (slabPhoto != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              slabPhoto!,
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: const Icon(
                              Icons.image_outlined,
                              color: AppColors.textMuted,
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: submitting ? null : pickSlabPhoto,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('슬랩사진 선택'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.blue,
                              side: const BorderSide(color: AppColors.blue),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary),
                      onChanged: (_) => setModal(() {}),
                      decoration: InputDecoration(
                        labelText: '판매가',
                        labelStyle: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                        suffixText: '원',
                        suffixStyle: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.divider,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.divider,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canSubmit ? submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          disabledBackgroundColor: Colors.white12,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '판매 등록',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (created && mounted) _loadData();
    } finally {
      priceCtrl.dispose();
    }
  }

  // ignore: unused_element
  Future<void> _loadPortfolio() async {
    if (_userId == null) return;
    try {
      final res = await ApiClient.get(
        '${ApiConstants.assets}/portfolio',
        params: {'userId': _userId},
      );
      if (mounted) {
        setState(() => _portfolio = res['data'] as Map<String, dynamic>?);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bg,
        foregroundColor: Colors.white,
        title: const Text('내 자산'),
        // Polish: 상단 + 버튼 제거. 자산 등록 동선은 하단 스캐너 버튼(FAB) 단일화 (feedback_scanner_only_asset_entry).
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white30),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildPortfolioSummary()),
                  SliverToBoxAdapter(child: _buildTabAndSortRow()),
                  // 내 매수 주문 탭 (index 2)
                  if (_tabIndex == 2) ...[
                    if (_myBuyOrders.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              '등록한 매수 호가가 없습니다.\n카드 상세에서 등록할 수 있습니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _buildBuyOrderRow(_myBuyOrders[i]),
                            childCount: _myBuyOrders.length,
                          ),
                        ),
                      ),
                  ]
                  else if (_filteredAssets.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState.noAssets(
                        onAdd: _tabIndex == 0
                            ? () => context.go('/scanner')
                            : null,
                      ),
                    )
                  else ...[
                    // 4차-Round3 Bento: 4장+이면 첫 카드 spotlight + 나머지 격자.
                    // Codex 권고 "균일 카드 → compact row + 강조 카드 혼합 bento"
                    if (_filteredAssets.length >= 4)
                      SliverToBoxAdapter(
                        child: _buildAssetSpotlight(_filteredAssets.first),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 0.62,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final offset = _filteredAssets.length >= 4 ? 1 : 0;
                            return _buildAssetGridItem(
                              _filteredAssets[index + offset],
                            );
                          },
                          childCount: _filteredAssets.length >= 4
                              ? _filteredAssets.length - 1
                              : _filteredAssets.length,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPortfolioSummary() {
    final totalMarketValue =
        (_portfolio?['totalMarketValue'] as num?)?.toDouble() ?? 0;
    final distinctCount = _portfolio?['distinctCardCount'] ?? 0;

    // 포트폴리오 총 수익률 계산 (purchasePrice 있는 카드만)
    double totalPurchase = 0;
    double totalCurrent = 0;
    for (final a in _assets) {
      final pp = (a['purchasePrice'] as num?)?.toDouble();
      if (pp == null || pp <= 0) continue;
      // 자산별 displayPrice 직접 사용 — 같은 cardId 여러 자산이 다른 language면 _marketPrices 캐시는 첫 가격만.
      final mp = (a['displayPrice'] as num?)?.toDouble();
      if (mp == null) continue;
      totalPurchase += pp;
      totalCurrent += mp;
    }
    final hasRate = totalPurchase > 0;
    final totalRate = hasRate
        ? (totalCurrent - totalPurchase) / totalPurchase * 100
        : 0.0;
    // 색상 정책: 양(>0)=빨강, 음(<0)=파랑, 변동 없음(=0)=회색.
    // 0.0%일 때 red 표시는 의미 충돌 (변동 없음 = neutral).
    final isFlat = totalRate.abs() < 0.05;  // -0.05 ~ 0.05% 는 변동 없음으로 처리
    final isPos = totalRate > 0;
    final rateColor = isFlat
        ? AppColors.textMuted
        : (isPos ? AppColors.red : AppColors.blue);

    // Polish Step 1 (2026-05-19): summary card 축소.
    // - margin top 8 → 6, padding 18 → (20,16,20,14), height ~144 → ~100
    // - radius 20 → 18 (살짝 sharp)
    // - "총 평가 자산" 12 → 13px, letterSpacing -0.2 (한글 가독)
    // - 금액 32 w900 → 30 w800 (덜 강조, 그러나 임팩트 유지)
    // - 수익률 + 보유 종수 → RichText 한 줄 (dot separator)
    // - 박스/border 유지 (보수)
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '총 평가 자산',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            // 4차-Round1: TweenedCounter — 자산 추가/삭제 시 부드러운 보간
            TweenedCounter(
              value: totalMarketValue,
              formatter: (v) => _formatPrice(v.toDouble()),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.0,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 6),
            // 수익률 + 보유 종수 한 줄. hasRate 없으면 보유 종수만.
            hasRate
                ? RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      children: [
                        TextSpan(
                          text: () {
                            final diff = totalCurrent - totalPurchase;
                            final sign = isFlat ? '' : (isPos ? '+' : '');
                            return '$sign${_formatPrice(diff)} ($sign${totalRate.toStringAsFixed(1)}%)';
                          }(),
                          // 색상 정책: >0 빨강, <0 파랑, =0 회색(변동 없음)
                          style: TextStyle(color: rateColor),
                        ),
                        const TextSpan(
                          text: '  ·  ',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                        TextSpan(
                          text: '$distinctCount종 보유',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    '$distinctCount종 보유',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  /// Polish Step 2 (2026-05-20): tab + sort 한 row 통합.
  /// - tab = text + underline (primary navigation, 토스/Apple HIG)
  /// - sort = 우측 dropdown trigger (secondary, BottomSheet popup)
  /// - 기존 chip pill 두 row (sort row 40 + tab row 56)을 한 row로
  Widget _buildTabAndSortRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _tabText('전체', 0),
          const SizedBox(width: 18),
          _tabText('판매중', 1),
          const SizedBox(width: 18),
          _tabText('내 매수', 2),
          const Spacer(),
          _sortDropdown(),
        ],
      ),
    );
  }

  Widget _tabText(String label, int index) {
    final selected = _tabIndex == index;
    // fixed height + strutStyle 로 w500/w700 baseline 미세 어긋남 방지.
    return GestureDetector(
      onTap: () {
        setState(() => _tabIndex = index);
        if (index == 2 && _myBuyOrders.isEmpty) _loadMyBuyOrders();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 38,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                label,
                strutStyle: const StrutStyle(
                  forceStrutHeight: true,
                  fontSize: 15,
                  height: 1.2,
                ),
                style: TextStyle(
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
                  height: 1.2,
                ),
              ),
            ),
            Container(
              height: 2.5,
              width: 22,
              decoration: BoxDecoration(
                color: selected ? AppColors.blue : Colors.transparent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel() {
    switch (_sortMode) {
      case _SortMode.rarity:
        return '등급순';
      case _SortMode.price:
        return '가격순';
      case _SortMode.name:
        return '이름순';
      case _SortMode.quantity:
        return '수량순';
    }
  }

  Widget _sortDropdown() {
    return GestureDetector(
      onTap: _showSortSheet,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sortLabel(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              _sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '정렬 기준',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _sortOption(ctx, '등급순', _SortMode.rarity),
            _sortOption(ctx, '가격순', _SortMode.price),
            _sortOption(ctx, '이름순', _SortMode.name),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(BuildContext ctx, String label, _SortMode mode) {
    final selected = _sortMode == mode;
    return InkWell(
      onTap: () {
        _onSortTap(mode);
        Navigator.pop(ctx);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.blue : AppColors.textPrimary,
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                color: AppColors.blue,
                size: 14,
              ),
            ],
            const Spacer(),
            if (selected)
              const Icon(Icons.check, color: AppColors.blue, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMyBuyOrders() async {
    try {
      final res = await ApiClient.get('/api/buy-orders/me');
      if (!mounted) return;
      setState(() {
        _myBuyOrders = List<Map<String, dynamic>>.from(res['data'] ?? []);
      });
    } catch (_) {}
  }

  /// 4차-Round4-4 Phase 5: 내 매수 호가 한 줄 row
  Widget _buildBuyOrderRow(Map<String, dynamic> order) {
    final cardName = order['cardName'] as String? ?? '';
    final imageUrl = order['cardImageUrl'] as String?;
    final rarity = order['rarityCode'] as String? ?? '';
    final price = (order['bidPrice'] as num?)?.toInt();
    final cardStatus = order['cardStatus'] as String? ?? 'RAW';
    final gc = order['gradingCompany'] as String?;
    final gv = order['gradeValue'] as String?;
    final qty = (order['qty'] as num?)?.toInt() ?? 1;
    final orderId = order['buyOrderId'] as String? ?? '';
    final cardId = order['cardId'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // 카드 thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CardImage(
              imageUrl: imageUrl,
              cdnFallbackUrl: imageUrl,
              width: 44, height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        cardStatus == 'GRADED' && gc != null && gv != null ? '$gc $gv' : 'RAW',
                        style: const TextStyle(color: AppColors.green, fontSize: 9.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (rarity.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(rarity, style: TextStyle(
                        color: AppColors.rarityColor(rarity),
                        fontSize: 10, fontWeight: FontWeight.w700,
                      )),
                    ],
                    if (qty > 1) ...[
                      const SizedBox(width: 4),
                      Text('× $qty', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  cardName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  price != null ? '${_formatPrice(price)}에 매수 희망' : '-',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
            onPressed: () => _confirmCancelBuyOrder(orderId, cardId),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelBuyOrder(String orderId, String cardId) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: '매수 호가 취소',
      message: '이 매수 호가를 취소하시겠어요?',
      confirmLabel: '취소하기',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ApiClient.delete('/api/buy-orders/$orderId');
      _loadMyBuyOrders();
    } catch (_) {}
  }

  /// 4차-Round3 Bento spotlight — 4장+ 보유 시 첫 카드를 큰 가로 row로.
  Widget _buildAssetSpotlight(Map<String, dynamic> asset) {
    final cardId = asset['cardId'] as String? ?? '';
    final cardData = asset['card'] as Map<String, dynamic>? ?? {};
    final cardName = cardData['name'] as String? ?? cardId;
    final rarity = cardData['rarityCode'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(cardData);
    final marketPrice = (asset['displayPrice'] as num?)?.toDouble();
    final purchasePrice = (asset['purchasePrice'] as num?)?.toDouble();
    final diff = (marketPrice != null && purchasePrice != null && purchasePrice > 0)
        ? marketPrice - purchasePrice
        : null;
    final rate = (diff != null && purchasePrice != null && purchasePrice > 0)
        ? diff / purchasePrice * 100
        : null;
    final premium = _isRarityPremium(rarity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg,
      ),
      child: Pressable(
        onTap: () async {
          final changed = await context.push<bool>(
            '/card/$cardId', extra: {'myAsset': asset},
          );
          if (changed == true && mounted) _loadData();
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: _rarityBorderColor(rarity),
              width: premium ? 1.0 : 0.5,
            ),
            boxShadow: premium
                ? [
                    BoxShadow(
                      color: AppColors.rarityGlow(rarity).withValues(alpha: 0.22),
                      blurRadius: 28,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : AppShadows.light(Colors.black),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.md, AppSpacing.lg,
                  ),
                  child: RarityAura(
                    rarity: rarity,
                    radius: 70,
                    intensity: 0.6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: CardImage(
                        imageUrl: imageUrl,
                        cdnFallbackUrl: resolveCdnImageUrl(cardData),
                        width: 96,
                        height: 134,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      0, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            if (rarity.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.rarityColor(rarity).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Text(
                                  rarity,
                                  style: TextStyle(
                                    color: AppColors.rarityColor(rarity),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'TOP 1',
                              style: AppText.label.copyWith(
                                color: AppColors.textMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          cardName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title.copyWith(
                            letterSpacing: -0.3, height: 1.2,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (marketPrice != null)
                          TweenedCounter(
                            value: marketPrice,
                            formatter: (v) => _formatPrice(v.toDouble()),
                            style: AppText.display.copyWith(
                              fontSize: 22, letterSpacing: -0.8,
                            ),
                          )
                        else
                          Text('—', style: AppText.title.copyWith(color: AppColors.textMuted)),
                        if (diff != null && rate != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${diff >= 0 ? '+' : ''}${_formatPrice(diff)} (${diff >= 0 ? '+' : ''}${rate.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              // 색상 정책 (feedback_color_policy.md): 양=빨강, 음=파랑.
                              color: diff >= 0 ? AppColors.red : AppColors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssetGridItem(Map<String, dynamic> asset) {
    final cardId = asset['cardId'] as String? ?? '';
    final marketPrice = (asset['displayPrice'] as num?)?.toDouble();
    final priceBasis = asset['displayPriceBasis'] as String?;
    final isRawFallback = priceBasis == 'RAW_FALLBACK';
    final purchasePrice = (asset['purchasePrice'] as num?)?.toDouble();
    final cardStatus = asset['cardStatus'] as String? ?? 'RAW';
    final language = asset['language'] as String? ?? 'KO';
    final gradingCompany = asset['gradingCompany'] as String?;
    final gradeValue = asset['gradeValue'] as String?;
    final estimatedGrade = (asset['estimatedGrade'] as num?)?.toDouble();
    final isSelling = asset['isSelling'] == true;
    final assetId = asset['assetId'] as String? ?? '';
    final cardData = asset['card'] as Map<String, dynamic>? ?? {};
    final cardName = cardData['name'] as String? ?? cardId;
    final rarity = cardData['rarityCode'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(cardData);

    // badgeLabel만 사용 (하단 정보 line의 'KO · RAW 6.5'). badge 컬러는
    // 90d94f3e badge 재배치 이후 미사용 → 제거.
    late final String badgeLabel;
    if (cardStatus == 'GRADED' && gradingCompany != null) {
      badgeLabel = '$gradingCompany${gradeValue != null ? " $gradeValue" : ""}';
    } else if (estimatedGrade != null) {
      badgeLabel = 'RAW ${estimatedGrade.toStringAsFixed(1)}';
    } else {
      badgeLabel = 'RAW';
    }

    // 4차-Round4: 풀 오버레이 디자인 — 카드 이미지 풀 + 하단 그라데이션 위 정보 (NFT 갤러리 패턴)
    final rarityColor = AppColors.rarityColor(rarity);
    final premium = _isRarityPremium(rarity);
    final rate = (marketPrice != null && purchasePrice != null && purchasePrice > 0)
        ? (marketPrice - purchasePrice) * 100.0 / purchasePrice
        : null;

    return Pressable(
      onTap: () async {
        final changed = await context.push<bool>(
          '/card/$cardId',
          extra: {'myAsset': asset},
        );
        if (changed == true && mounted) _loadData();
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: premium
                ? AppColors.rarityGlow(rarity).withValues(alpha: 0.55)
                : AppColors.divider,
            width: premium ? 1.2 : 0.6,
          ),
          boxShadow: premium
              ? [
                  BoxShadow(
                    color: AppColors.rarityGlow(rarity).withValues(alpha: 0.30),
                    blurRadius: 18,
                    spreadRadius: 0.5,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : AppShadows.light(Colors.black),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg - 1),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 카드 이미지 — 풀 채움
              CardImage(
                imageUrl: imageUrl,
                cdnFallbackUrl: resolveCdnImageUrl(cardData),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
              // 하단 그라데이션 overlay (정보 가독성)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.45, 0.75, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
              ),
              // 좌상단: 레어도 단일 chip (KO/등급은 하단 정보 line으로 이동 — 잘림 해소)
              if (rarity.isNotEmpty)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: rarityColor.withValues(alpha: 0.6),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      rarity,
                      style: TextStyle(
                        color: rarityColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              // 우상단: isSelling=true → '판매중' chip, false → close X (중복 X)
              if (isSelling)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Text(
                      '판매중',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                )
              else
                // 판매중 X → 우상단 close X (자산 삭제)
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () => _confirmDelete(assetId),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white60,
                        size: 12,
                      ),
                    ),
                  ),
                ),
              // 하단: 카드명 + 가격 + 손익률
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cardName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.1,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    // 정보 line — KO · RAW 6.5 (좌상단에서 이동)
                    Text(
                      '$language · $badgeLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        height: 1.0,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 3),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  marketPrice != null ? _formatPrice(marketPrice) : '시세 없음',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: marketPrice != null ? Colors.white : Colors.white60,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              if (isRawFallback) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    'RAW 기준',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (rate != null)
                          Text(
                            '${rate >= 0 ? '+' : ''}${rate.toStringAsFixed(1)}%',
                            style: TextStyle(
                              // 색상 정책 (feedback_color_policy.md): 양=빨강, 음=파랑.
                              color: rate >= 0 ? AppColors.red : AppColors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 3),
                              ],
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
    );
  }

  // 자산 추가 옵션 sheet — 상단 + 제거 후 일시 unused. 다음 Step (ghost tile)에서 재사용 예정.
  // ignore: unused_element
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
              const Text(
                '자산 추가',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildOptionTile(
                icon: Icons.qr_code_scanner,
                label: '스캔으로 추가',
                sub: '카드를 카메라로 스캔해서 추가',
                onTap: () async {
                  Navigator.pop(context);
                  final changed = await context.push<bool>('/scanner');
                  if (changed == true && mounted) {
                    _loadData();
                  }
                },
              ),
              const SizedBox(height: 10),
              _buildOptionTile(
                icon: Icons.search_rounded,
                label: '직접 검색',
                sub: '카드 이름으로 검색해서 추가 (RAW)',
                onTap: () {
                  Navigator.pop(context);
                  _showCardSearch();
                },
              ),
              const SizedBox(height: 10),
              _buildOptionTile(
                icon: Icons.verified_rounded,
                label: '외부 감정 카드 등록',
                sub: 'PSA · BRG 등급 카드 보유 중이신가요?',
                onTap: () {
                  Navigator.pop(context);
                  _showGradedCardAdd();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCardSearch() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;
    bool added = false;
    String selectedLanguage = 'KO';

    Future<void> doSearch(String q, StateSetter setModal) async {
      if (q.trim().isEmpty) {
        setModal(() { results = []; searching = false; });
        return;
      }
      setModal(() => searching = true);
      try {
        final res = await ApiClient.get('/api/cards/search', params: {'name': q.trim(), 'size': 15});
        final items = (res['data'] as Map?)?['content'] as List? ?? res['data'] as List? ?? [];
        setModal(() {
          results = items.cast<Map<String, dynamic>>();
          searching = false;
        });
      } catch (_) {
        setModal(() => searching = false);
      }
    }

    Future<void> registerRaw(Map<String, dynamic> card, StateSetter setModal) async {
      final cardId = card['cardId'] as String? ?? '';
      if (cardId.isEmpty || _userId == null) return;
      setModal(() => searching = true);
      try {
        await ApiClient.post(ApiConstants.assets, {
          'data': {
            'userId': _userId,
            'cardId': cardId,
            'quantity': 1,
            'cardStatus': 'RAW',
            'language': selectedLanguage,
          },
        });
        AssetNotifier.instance.notifyChanged();
        added = true;
        if (mounted) Navigator.pop(context);
      } catch (_) {
        setModal(() => searching = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('등록 실패'), backgroundColor: Colors.red),
          );
        }
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '카드 검색',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: ['KO', 'JP', 'EN'].map((lang) {
                    final sel = selectedLanguage == lang;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setModal(() => selectedLanguage = lang),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.blue : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: sel ? AppColors.blue : AppColors.divider),
                          ),
                          child: Text(
                            lang,
                            style: TextStyle(
                              color: sel ? Colors.white : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '카드 이름 입력...',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => doSearch(v, setModal),
                ),
              ),
              const SizedBox(height: 8),
              if (searching)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final card = results[i];
                      final name = card['name'] as String? ?? '';
                      final rarity = card['rarityCode'] as String? ?? '';
                      final imageUrl = resolveCardImageUrl(card);
                      final cdnUrl = resolveCdnImageUrl(card);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: CardImage(
                          imageUrl: imageUrl,
                          cdnFallbackUrl: cdnUrl,
                          width: 36,
                          height: 50,
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          rarity.isNotEmpty ? rarity : '-',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                        trailing: const Icon(Icons.add_circle_outline_rounded, color: AppColors.blue),
                        onTap: () => registerRaw(card, setModal),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    searchCtrl.dispose();
    if (added && mounted) _loadData();
  }

  Future<void> _showGradedCardAdd() async {
    final picker = ImagePicker();
    final certCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final searchCtrl = TextEditingController();

    Map<String, dynamic>? selectedCard;
    String? gradingCompany;
    String? gradeValue;
    File? slabPhoto;
    List<Map<String, dynamic>> searchResults = [];
    bool searching = false;
    bool submitting = false;
    bool added = false;
    String selectedLanguage = 'KO';

    const companies = ['PSA', 'BRG'];
    const grades = ['10', '9', '8', '7', '6', '5'];

    Future<void> doSearch(String q, StateSetter setModal) async {
      if (q.trim().isEmpty) {
        setModal(() { searchResults = []; searching = false; });
        return;
      }
      setModal(() => searching = true);
      try {
        final res = await ApiClient.get('/api/cards/search', params: {'name': q.trim(), 'size': 15});
        final items = (res['data'] as Map?)?['content'] as List? ?? res['data'] as List? ?? [];
        setModal(() {
          searchResults = items.cast<Map<String, dynamic>>();
          searching = false;
        });
      } catch (_) {
        setModal(() => searching = false);
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final canSubmit = selectedCard != null &&
              gradingCompany != null &&
              gradeValue != null &&
              !submitting;

          Future<void> pickPhoto() async {
            final picked = await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 90,
              maxWidth: 1200,
            );
            if (picked != null) setModal(() => slabPhoto = File(picked.path));
          }

          Future<void> submit() async {
            if (!canSubmit) return;
            final cardId = selectedCard!['cardId'] as String? ?? '';
            if (cardId.isEmpty || _userId == null) return;
            setModal(() => submitting = true);
            try {
              final purchasePrice = int.tryParse(priceCtrl.text.trim().replaceAll(',', ''));
              final body = <String, dynamic>{
                'userId': _userId,
                'cardId': cardId,
                'quantity': 1,
                'cardStatus': 'GRADED',
                'language': selectedLanguage,
                'gradingCompany': gradingCompany,
                'gradeValue': gradeValue,
                if (certCtrl.text.trim().isNotEmpty) 'certNumber': certCtrl.text.trim(),
                if (purchasePrice != null && purchasePrice > 0) 'purchasePrice': purchasePrice,
              };
              final res = await ApiClient.post(ApiConstants.assets, {'data': body});
              final newAssetId = (res['data'] as Map<String, dynamic>?)?['assetId'] as String?;
              if (newAssetId != null && slabPhoto != null) {
                await ApiClient.uploadFile(
                  '${ApiConstants.assets}/$newAssetId/slab-image',
                  slabPhoto!.path,
                  field: 'slab_image',
                );
              }
              AssetNotifier.instance.notifyChanged();
              added = true;
              if (mounted) Navigator.pop(context);
            } catch (_) {
              setModal(() => submitting = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('등록 실패'), backgroundColor: Colors.red),
                );
              }
            }
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.92,
            minChildSize: 0.6,
            maxChildSize: 0.97,
            builder: (_, scrollCtrl) => SingleChildScrollView(
              controller: scrollCtrl,
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '외부 감정 카드 등록',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 카드 검색
                  const Text('카드 검색', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (selectedCard != null) ...[
                    GestureDetector(
                      onTap: () => setModal(() { selectedCard = null; searchCtrl.clear(); searchResults = []; }),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            CardImage(
                              imageUrl: resolveCardImageUrl(selectedCard!),
                              cdnFallbackUrl: resolveCdnImageUrl(selectedCard!),
                              width: 32, height: 44,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedCard!['name'] as String? ?? '',
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    selectedCard!['rarityCode'] as String? ?? '-',
                                    style: const TextStyle(color: AppColors.blue, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: searchCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '카드 이름 입력...',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => doSearch(v, setModal),
                    ),
                    if (searching)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2)),
                      )
                    else if (searchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.divider),
                        ),
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: searchResults.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (_, i) {
                            final card = searchResults[i];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              leading: CardImage(
                                imageUrl: resolveCardImageUrl(card),
                                cdnFallbackUrl: resolveCdnImageUrl(card),
                                width: 28, height: 38,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              title: Text(
                                card['name'] as String? ?? '',
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                card['rarityCode'] as String? ?? '-',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                              ),
                              onTap: () => setModal(() {
                                selectedCard = card;
                                searchResults = [];
                                searchCtrl.clear();
                              }),
                            );
                          },
                        ),
                      ),
                  ],
                  const SizedBox(height: 20),

                  // 카드 언어
                  const Text('카드 언어', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: ['KO', 'JP', 'EN'].map((lang) {
                      final sel = selectedLanguage == lang;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setModal(() => selectedLanguage = lang),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.blue : AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: sel ? AppColors.blue : AppColors.divider),
                            ),
                            child: Text(
                              lang,
                              style: TextStyle(
                                color: sel ? Colors.white : AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // 감정사
                  const Text('감정사', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: companies.map((c) {
                      final sel = gradingCompany == c;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setModal(() => gradingCompany = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.gold.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: sel ? AppColors.gold : AppColors.divider),
                            ),
                            child: Text(
                              c,
                              style: TextStyle(
                                color: sel ? AppColors.gold : AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  // PSA10 + EN/JP는 실제 시세 데이터 있을 확률 ↑ → 안내 숨김.
                  if (!((selectedLanguage == 'EN' || selectedLanguage == 'JP')
                      && gradingCompany == 'PSA'
                      && gradeValue == '10')) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '데이터에 없는 등급은 RAW 시세로 대체됩니다.',
                              style: TextStyle(
                                color: Colors.amber.shade200,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // 등급
                  const Text('등급', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: grades.map((g) {
                      final sel = gradeValue == g;
                      return GestureDetector(
                        onTap: () => setModal(() => gradeValue = g),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.blue.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: sel ? AppColors.blue : AppColors.divider),
                          ),
                          child: Text(
                            g,
                            style: TextStyle(
                              color: sel ? AppColors.blue : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // 인증번호 (optional)
                  const Text('인증번호 (선택)', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: certCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'ex) 12345678',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 구매가 (optional)
                  const Text('구매가 (선택)', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      suffixText: '원',
                      suffixStyle: const TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 슬랩 사진 (optional)
                  const Text('슬랩 사진 (선택)', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: pickPhoto,
                    child: slabPhoto != null
                        ? Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(slabPhoto!, height: 160, width: double.infinity, fit: BoxFit.cover),
                              ),
                              GestureDetector(
                                onTap: () => setModal(() => slabPhoto = null),
                                child: Container(
                                  margin: const EdgeInsets.all(6),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                                ),
                              ),
                            ],
                          )
                        : Container(
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.divider, style: BorderStyle.solid),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_rounded, color: AppColors.textMuted, size: 32),
                                SizedBox(height: 6),
                                Text('갤러리에서 선택', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canSubmit ? submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        disabledBackgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              '등록',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    certCtrl.dispose();
    priceCtrl.dispose();
    searchCtrl.dispose();
    if (added && mounted) _loadData();
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    required String sub,
    required VoidCallback onTap,
  }) {
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
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String assetId) async {
    final asset = _assets.firstWhere(
      (a) => a['assetId'] == assetId,
      orElse: () => {},
    );
    if (asset['isSelling'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('판매 중인 카드는 삭제할 수 없습니다. 먼저 판매를 내려주세요.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    final ok = await AppConfirmDialog.show(
      context,
      title: '자산 삭제',
      message: '이 카드를 자산에서 삭제할까요?',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (ok == true) await _deleteAsset(assetId);
  }

  // ignore: unused_element
  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '-';
    final p = ((price as num).toInt() / 10).round() * 10;
    if (p <= 0) return '0원';
    final s = p.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '$s원';
  }
}
