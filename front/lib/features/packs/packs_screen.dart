import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';

class PacksScreen extends StatefulWidget {
  const PacksScreen({super.key});

  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  List<Map<String, dynamic>> _packs = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _search = '';
  String _selectedType = '전체';
  final _searchCtrl = TextEditingController();

  static const _types = ['전체', '부스터팩', '덱', '하이클래스팩', '프로모', '특별판'];
  static const _typeMap = {
    '부스터팩': 'BOOSTER',
    '덱': 'DECK',
    '하이클래스팩': 'HIGH_CLASS_PACK',
    '프로모': 'PROMO',
    '특별판': 'SPECIAL',
  };

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPacks() async {
    try {
      final res = await ApiClient.get('/api/products');
      final data = List<Map<String, dynamic>>.from(res['data'] ?? []);
      if (!mounted) return;
      setState(() {
        _packs = data;
        _loading = false;
        _applyFilter();
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    setState(() {
      _filtered = _packs.where((p) {
        final name = (p['name'] as String? ?? '').toLowerCase();
        final type = p['productType'] as String? ?? '';
        final matchSearch = _search.isEmpty || name.contains(_search.toLowerCase());
        final matchType = _selectedType == '전체' ||
            type == (_typeMap[_selectedType] ?? _selectedType);
        return matchSearch && matchType;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text('팩', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              onChanged: (v) { _search = v; _applyFilter(); },
              decoration: InputDecoration(
                hintText: '팩 이름 검색',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                        onPressed: () { _searchCtrl.clear(); _search = ''; _applyFilter(); })
                    : null,
                filled: true,
                fillColor: AppColors.surfaceCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildTypeFilter(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('팩을 찾을 수 없습니다',
                            style: TextStyle(color: AppColors.textMuted)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) => _buildPackItem(_filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: _types.map((t) {
          final selected = _selectedType == t;
          return GestureDetector(
            onTap: () { setState(() => _selectedType = t); _applyFilter(); },
            child: Center(
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? AppColors.blue : AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: selected ? AppColors.blue : AppColors.divider),
                ),
                child: Text(t, style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPackItem(Map<String, dynamic> pack) {
    final productId = pack['productId'] ?? '';
    final name = pack['name'] ?? '';
    final seriesName = pack['seriesName'] ?? '';
    final productType = pack['productType'] ?? '';

    final parts = name.split('「');
    final mainName = parts[0].trim();
    final subName = parts.length > 1 ? '「${parts[1]}' : null;

    return GestureDetector(
      onTap: () => context.push('/product/$productId', extra: {'productName': name, 'seriesName': seriesName}),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.inventory_2_rounded, color: AppColors.blue, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mainName,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subName != null)
                    Text(subName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  if (seriesName.isNotEmpty)
                    Text(seriesName, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            _buildTypeBadge(productType),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    String label;
    Color color;
    switch (type) {
      case 'BOOSTER': label = '부스터'; color = AppColors.blue; break;
      case 'HIGH_CLASS_PACK': label = '하이클래스'; color = AppColors.gold; break;
      case 'DECK': label = '덱'; color = AppColors.green; break;
      case 'PROMO': label = '프로모'; color = AppColors.rarityCSR; break;
      default: label = type.isNotEmpty ? type : '기타'; color = AppColors.textMuted; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
