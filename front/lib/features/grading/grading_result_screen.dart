import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';

class GradingResultScreen extends StatefulWidget {
  final List<File> photos;
  const GradingResultScreen({super.key, required this.photos});
  @override
  State<GradingResultScreen> createState() => _GradingResultScreenState();
}

class _GradingResultScreenState extends State<GradingResultScreen> {
  Map<String, dynamic>? _result;
  bool _loading = true;
  String? _error;

  static const _photoKeys = [
    'front', 'back',
    'corner_front_tl', 'corner_front_tr', 'corner_front_bl', 'corner_front_br',
    'corner_back_tl', 'corner_back_tr', 'corner_back_bl', 'corner_back_br',
  ];

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      String userId = 'guest';
      try {
        final userRes = await ApiClient.get('/api/users/me');
        userId = (userRes['data'] as Map<String, dynamic>?)?['userId'] as String? ?? 'guest';
      } catch (_) {}

      final files = <String, File>{};
      for (int i = 0; i < widget.photos.length; i++) {
        files[_photoKeys[i]] = widget.photos[i];
      }
      final res = await ApiClient.postMultipart(
        ApiConstants.gradingAnalyze,
        files: files,
        fields: {'userId': userId},
      );
      if (mounted) setState(() { _result = res['data']; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg, elevation: 0,
        title: const Text('분석 결과', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: AppColors.blue),
              SizedBox(height: 16),
              Text('사진 분석 중...', style: TextStyle(color: AppColors.textSecondary)),
            ]))
          : _error != null
              ? Center(child: Text('분석 실패: $_error', style: const TextStyle(color: AppColors.red)))
              : _buildResult(),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final total = (r['totalScore'] as num).toDouble();
    final heavy = r['heavyWhitening'] as bool? ?? false;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A3A6A), Color(0xFF0D2040)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.blue.withOpacity(0.3)),
          ),
          child: Column(children: [
            const Text('예상 등급', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(total.toStringAsFixed(1),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 56, fontWeight: FontWeight.bold)),
            Text('/ 10.0', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
            if (heavy) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('⚠ 심한 화이트닝 감지됨', style: TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(children: [
            _buildScoreRow('센터링', r['centeringScore']),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('코너', r['cornerScore']),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('표면', r['surfaceScore']),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('화이트닝', r['whiteningScore']),
          ]),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => context.go('/grading'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blue,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('다시 분석하기', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildScoreRow(String label, dynamic scoreRaw) {
    final score = (scoreRaw as num).toDouble();
    final color = score >= 9.0 ? AppColors.green : score >= 7.0 ? AppColors.blue : AppColors.red;
    return Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
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
      Text(score.toStringAsFixed(1), style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
    ]);
  }
}
