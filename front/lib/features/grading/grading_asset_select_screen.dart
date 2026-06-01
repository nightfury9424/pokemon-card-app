import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class GradingAssetSelectScreen extends StatefulWidget {
  const GradingAssetSelectScreen({super.key});

  @override
  State<GradingAssetSelectScreen> createState() =>
      _GradingAssetSelectScreenState();
}

class _GradingAssetSelectScreenState extends State<GradingAssetSelectScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _assets = [];
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final meRes = await ApiClient.get('/api/users/me');
      final userId = (meRes['data'] as Map<String, dynamic>?)?['userId'] as String?;
      if (userId == null) {
        if (mounted) setState(() {
          _error = '로그인이 필요해요';
          _loading = false;
        });
        return;
      }
      final res = await ApiClient.get(
        ApiConstants.assets,
        params: {'userId': userId},
      );
      final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
      if (mounted) setState(() {
        _assets = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.trim().isEmpty) return _assets;
    final q = _query.trim().toLowerCase();
    return _assets.where((a) {
      final cardData = a['card'] as Map<String, dynamic>? ?? {};
      final name = (cardData['name'] as String? ?? '').toLowerCase();
      final id = (a['cardId'] as String? ?? '').toLowerCase();
      return name.contains(q) || id.contains(q);
    }).toList();
  }

  void _selectAsset(Map<String, dynamic> asset) {
    final cardData = asset['card'] as Map<String, dynamic>? ?? {};
    final assetId = asset['assetId'] as String?;
    final cardId = asset['cardId'] as String?;
    final cardName = cardData['name'] as String? ?? cardId;
    if (assetId == null || cardId == null) return;
    context.push('/grading/capture', extra: {
      'assetId': assetId,
      'cardId': cardId,
      'cardName': cardName,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '그레이딩할 카드 선택',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _error != null
              ? _buildErrorView()
              : _buildContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(_error ?? '오류',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
        ]),
      ),
    );
  }

  Widget _buildContent() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, color: AppColors.blue, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI 그레이딩 결과는 선택한 자산에 저장돼요',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
              ),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: '카드명 검색',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
            filled: true,
            fillColor: AppColors.surfaceCard,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.divider),
            ),
          ),
        ),
      ),
      Expanded(
        child: _assets.isEmpty
            ? _buildEmptyState()
            : _filtered.isEmpty
                ? const Center(
                    child: Text('검색 결과 없음',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildAssetTile(_filtered[i]),
                  ),
      ),
    ]);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.style_outlined, color: AppColors.textMuted, size: 56),
          const SizedBox(height: 16),
          const Text('아직 등록한 자산이 없어요',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('카드 스캐너로 등록하면 그레이딩을 시작할 수 있어요',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => context.push('/scanner'),
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
            label: const Text('카드 스캐너로 등록',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildAssetTile(Map<String, dynamic> asset) {
    final cardData = asset['card'] as Map<String, dynamic>? ?? {};
    final cardName = cardData['name'] as String? ?? asset['cardId'] as String? ?? '';
    final rarity = cardData['rarityCode'] as String? ?? '';
    final qty = (asset['quantity'] as num?)?.toInt() ?? 1;
    final displayPrice = (asset['displayPrice'] as num?)?.toInt();
    final imageUrl = resolveCardImageUrl(cardData);

    return Material(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _selectAsset(asset),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 48, height: 66,
                child: imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(color: AppColors.divider))
                    : Container(color: AppColors.divider),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cardName,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (rarity.isNotEmpty) ...[
                      Text(rarity,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                      const SizedBox(width: 8),
                    ],
                    Text('${qty}장',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                    if (displayPrice != null && displayPrice > 0) ...[
                      const SizedBox(width: 8),
                      Text('${displayPrice.toString()}원',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ]),
        ),
      ),
    );
  }
}
