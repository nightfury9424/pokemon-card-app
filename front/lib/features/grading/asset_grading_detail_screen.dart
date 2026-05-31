import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/auth_image.dart';

class AssetGradingDetailScreen extends StatefulWidget {
  final String assetId;
  const AssetGradingDetailScreen({super.key, required this.assetId});

  @override
  State<AssetGradingDetailScreen> createState() =>
      _AssetGradingDetailScreenState();
}

class _AssetGradingDetailScreenState extends State<AssetGradingDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _asset;
  Map<String, dynamic>? _frontImage;
  Map<String, dynamic>? _backImage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final assetRes =
          await ApiClient.get('${ApiConstants.assets}/${widget.assetId}');
      final assetData = assetRes['data'] as Map<String, dynamic>?;

      List<Map<String, dynamic>> images = [];
      try {
        final imgRes = await ApiClient.get(
            '${ApiConstants.assets}/${widget.assetId}/images');
        final data = imgRes['data'];
        if (data is List) {
          images = List<Map<String, dynamic>>.from(data);
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _asset = assetData;
          _frontImage =
              images.where((i) => i['imageType'] == 'FRONT').firstOrNull;
          _backImage =
              images.where((i) => i['imageType'] == 'BACK').firstOrNull;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _reanalyze() {
    final a = _asset;
    if (a == null) return;
    final cardData = a['card'] as Map<String, dynamic>? ?? {};
    context.push('/grading/capture', extra: {
      'assetId': widget.assetId,
      'cardId': a['cardId'] as String?,
      'cardName': cardData['name'] as String?,
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
        title: const Text('AI 컨디션 분석',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
    final a = _asset;
    if (a == null) return _buildError();

    final estimatedGrade = (a['estimatedGrade'] as num?)?.toDouble();
    final centering = (a['centeringScore'] as num?)?.toDouble();
    final corner = (a['cornerScore'] as num?)?.toDouble();
    final surface = (a['surfaceScore'] as num?)?.toDouble();
    final whitening = (a['whiteningScore'] as num?)?.toDouble();
    final centeringRatio = a['centeringRatio'] as String?;
    final analyzedAt = a['gradingAnalyzedAt'] as String?;
    final appAnalysisId = a['certNumber'] as String?;

    if (estimatedGrade == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.analytics_outlined, color: AppColors.textMuted, size: 56),
            const SizedBox(height: 16),
            const Text('아직 AI 컨디션 분석을 진행하지 않았어요',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _reanalyze,
              icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              label: const Text('분석 시작', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ]),
        ),
      );
    }

    final gradeColor = estimatedGrade >= 9.0
        ? AppColors.green
        : estimatedGrade >= 7.0 ? AppColors.blue : AppColors.red;

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A3A6A), Color(0xFF0D2040)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Text('PokeFolio AI 컨디션 분석',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            const Text('예상 컨디션 점수', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(estimatedGrade.toStringAsFixed(1),
                style: TextStyle(color: gradeColor, fontSize: 56, fontWeight: FontWeight.bold)),
          ]),
        ),
        if (centering != null) ...[
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(children: [
              _row('센터링', centering, sub: centeringRatio),
              const Divider(color: AppColors.divider, height: 20),
              _row('코너', corner ?? 0),
              const Divider(color: AppColors.divider, height: 20),
              _row('표면', surface ?? 0),
              const Divider(color: AppColors.divider, height: 20),
              _row('화이트닝', whitening ?? 0),
            ]),
          ),
        ],
        if (_frontImage != null || _backImage != null) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('촬영 사진',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              if (_frontImage != null)
                Expanded(child: _photoCard('앞면', _frontImage!['imageUrl'] as String?)),
              if (_frontImage != null && _backImage != null) const SizedBox(width: 10),
              if (_backImage != null)
                Expanded(child: _photoCard('뒷면', _backImage!['imageUrl'] as String?)),
            ]),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (analyzedAt != null) ...[
                Text('분석일 · ${_formatDate(analyzedAt)}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
              ],
              if (appAnalysisId != null && appAnalysisId.isNotEmpty)
                Text('앱 분석 ID · $appAnalysisId',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
                  '감점 사유 상세는 다시 분석 시 확인할 수 있어요',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: ElevatedButton.icon(
            onPressed: _reanalyze,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: const Text('다시 분석하기',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blue,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, double score, {String? sub}) {
    final color = score >= 9.0 ? AppColors.green : score >= 7.0 ? AppColors.blue : AppColors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(width: 80, child: Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 10.0,
              minHeight: 8,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(score.toStringAsFixed(1),
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ]),
      if (sub != null && sub.isNotEmpty) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 80),
          child: Text(sub, style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w500)),
        ),
      ],
    ]);
  }

  Widget _photoCard(String label, String? url) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(
        aspectRatio: 63.0 / 88.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url != null
              ? AuthImage(url: url, fit: BoxFit.cover)
              : Container(color: AppColors.divider),
        ),
      ),
      const SizedBox(height: 6),
      Text(label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
