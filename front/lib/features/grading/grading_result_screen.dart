import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import '../../core/network/api_client.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/constants/api_constants.dart';
import '../../core/notifiers/asset_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import 'grading_models.dart';

class GradingResultScreen extends StatefulWidget {
  final List<File> photos;
  final String? assetId;
  final String? cardId;
  final String? cardName;
  final Map<String, double>? frameRect;
  const GradingResultScreen({
    super.key,
    required this.photos,
    this.assetId,
    this.cardId,
    this.cardName,
    this.frameRect,
  });
  @override
  State<GradingResultScreen> createState() => _GradingResultScreenState();
}

class _GradingResultScreenState extends State<GradingResultScreen> {
  Map<String, dynamic>? _result;
  GradingResult? _parsed;
  bool _loading = true;
  String? _error;

  static const _photoKeys = ['front_image', 'back_image'];

  static const _sideKo = {'front': '앞면', 'back': '뒷면'};
  static const _positionKo = {
    'top_left': '좌상단',
    'top_right': '우상단',
    'bottom_left': '좌하단',
    'bottom_right': '우하단',
    'center': '중앙',
    'center_left': '좌측 중앙',
    'middle_right': '중앙 우측',
  };
  static const _typeKo = {
    'corner': '코너 마모 후보',
    'whitening': '백화 후보 영역',
    'scratch': '스크래치 후보',
    'dent': '찍힘 후보',
    'centering': '센터링 편차',
    'surface': '표면 이상 후보',
    'edge': '엣지 마모 후보',
  };

  String _humanReasonLabel(DeductionReason r) {
    final side = _sideKo[r.side] ?? '';
    final pos = _positionKo[r.position] ?? '';
    final type = _typeKo[r.type] ?? r.type;
    final loc = [side, pos].where((s) => s.isNotEmpty).join(' ');
    return loc.isNotEmpty ? '$loc $type' : type;
  }

  @override
  void dispose() {
    for (final f in widget.photos) {
      try {
        if (f.existsSync()) f.deleteSync();
        final resized = File('${f.parent.path}/resized_${f.uri.pathSegments.last}');
        if (resized.existsSync()) resized.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  // 업로드 전 리사이즈 (긴 변 기준 1200px, JPEG 85%)
  Future<File> _resizePhoto(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return file;
      final resized = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? 1200 : -1,
        height: decoded.width > decoded.height ? -1 : 1200,
      );
      final jpg = img.encodeJpg(resized, quality: 85);
      final tmp = File('${file.parent.path}/resized_${file.uri.pathSegments.last}');
      await tmp.writeAsBytes(jpg);
      return tmp;
    } catch (_) {
      return file;
    }
  }

  Future<void> _analyze() async {
    try {
      String userId = 'guest';
      try {
        final userRes = await ApiClient.get('/api/users/me');
        userId = (userRes['data'] as Map<String, dynamic>?)?['userId'] as String? ?? 'guest';
      } catch (_) {}

      // 리사이즈 후 업로드 (20MB → ~2MB)
      final files = <String, File>{};
      for (int i = 0; i < widget.photos.length; i++) {
        files[_photoKeys[i]] = await _resizePhoto(widget.photos[i]);
      }
      final fields = <String, String>{
        'userId': userId,
        if (widget.cardId != null) 'cardId': widget.cardId!,
      };
      final fr = widget.frameRect;
      if (fr != null) {
        fields['frame_x'] = (fr['frame_x'] ?? 0).toString();
        fields['frame_y'] = (fr['frame_y'] ?? 0).toString();
        fields['frame_w'] = (fr['frame_w'] ?? 1).toString();
        fields['frame_h'] = (fr['frame_h'] ?? 1).toString();
      }
      final res = await ApiClient.postMultipart(
        ApiConstants.gradingAnalyze,
        files: files,
        fields: fields,
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 120),
      );
      final data = res['data'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _result = data;
          _parsed = data != null ? GradingResult.fromJson(data) : null;
          _loading = false;
        });
      }
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('분석 결과', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: AppColors.blue),
              SizedBox(height: 16),
              Text('사진 분석 중...', style: TextStyle(color: AppColors.textSecondary)),
            ]))
          : _error != null
              ? _buildErrorView()
              : (_isRetakeBlocked() ? _buildRetakeView() : _buildResult()),
    );
  }

  bool _isRetakeBlocked() {
    final p = _parsed;
    if (p == null) return false;
    return p.retakeRequired || p.captureQuality == 'bad';
  }

  Widget _buildRetakeView() {
    final p = _parsed!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: AppColors.textMuted, size: 56),
            const SizedBox(height: 20),
            const Text('사진이 선명하지 않아요',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 10),
            Text(
              p.retakeReason.isNotEmpty
                  ? p.retakeReason
                  : '카드를 프레임 안에 맞춘 뒤 다시 촬영해 주세요',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => context.pop('retake'),
              icon: const Icon(Icons.refresh),
              label: const Text('다시 촬영하기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradeCard() {
    final p = _parsed;
    if (p == null) return const SizedBox.shrink();
    final colorHex = p.gradeColor.replaceAll('#', '');
    final color = Color(int.parse('FF$colorHex', radix: 16));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.center,
          child: Text(p.grade,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.totalScoreDisplay.toStringAsFixed(1),
                  style: TextStyle(
                      color: color,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      height: 1.0)),
              const SizedBox(height: 4),
              const Text('PokeFolio AI 자체 평가',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              if (p.deductionReasons.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_lowestMetricLine(p),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 12)),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  String _lowestMetricLine(GradingResult p) {
    final metrics = {
      '센터링': p.centeringScore,
      '코너': p.cornerScore,
      '표면': p.surfaceScore,
      '백화': p.whiteningScore,
      '엣지': p.edgeScore,
    };
    final lowest = metrics.entries.reduce((a, b) => a.value <= b.value ? a : b);
    return '${lowest.key} 항목이 가장 낮게 측정되었어요 (${lowest.value.toStringAsFixed(1)})';
  }

  Widget _buildQualityBanner() {
    final p = _parsed;
    if (p == null) return const SizedBox.shrink();
    final showWarning = p.captureQuality == 'warning' || p.screenSuspected;
    if (!showWarning) return const SizedBox.shrink();
    final msg = p.screenSuspected && p.screenSuspectReason.isNotEmpty
        ? p.screenSuspectReason
        : '촬영 품질이 낮아 분석 정확도가 떨어질 수 있어요';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFC76A)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: const TextStyle(
                  color: Color(0xFF92400E), fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => context.pop(),
          child: const Text('다시 찍기',
              style: TextStyle(
                  color: Color(0xFFD97706),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'major':    return const Color(0xFFDC2626);
      case 'moderate': return const Color(0xFFD97706);
      default:         return const Color(0xFF6B7280);
    }
  }

  Widget _severityChip(String severity) {
    final (label, color) = switch (severity) {
      'major' => ('심함', const Color(0xFFDC2626)),
      'moderate' => ('보통', const Color(0xFFD97706)),
      _ => ('경미', const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _retryAnalyze() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _result = null;
      _loading = true;
    });
    _analyze();
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.textMuted, size: 48),
            const SizedBox(height: 16),
            const Text(
              '분석에 실패했어요.\n사진을 다시 확인한 뒤 재시도해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _retryAnalyze,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(180, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('다시 시도', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final total = (r['totalScore'] as num).toDouble();
    final heavy = r['heavyWhitening'] as bool? ?? false;
    final confidence = (r['detectionConfidence'] as num?)?.toDouble() ?? 1.0;
    final identityVerified = (r['identityVerified'] as bool?) ?? (r['identity_verified'] as bool?) ?? true;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _buildQualityBanner(),
        _buildGradeCard(),
        const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('상세 분석',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600))),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
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
            // 두 줄 neutral grey 배지 — 56pt 숫자 위에 맥락 먼저 인식시킴.
            // gold/red 금지 (프리미엄/경고 느낌 → 외부 인증 또는 위험으로 오해 가능).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('AI 예측', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('외부 등급사 아님', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('예상 등급', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(total.toStringAsFixed(1),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 56, fontWeight: FontWeight.bold)),
            Text(
              '${(total - 1.0).clamp(1.0, 10.0).toStringAsFixed(1)} ~ ${(total + 1.0).clamp(1.0, 10.0).toStringAsFixed(1)} 예상 범위',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            // 상시 disclaimer — confidence 높아도 항상 표시 (공식 등급 오해 방지).
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '앱의 AI 예측 결과이며, 실제 PSA/BRG 등급 또는 인증 결과와 다를 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
              ),
            ),
            if (confidence < 0.6) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('⚠ 카드 인식 실패 — 재촬영 권장', style: TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            ] else if (confidence < 0.85) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('⚠ 카드 인식 불완전 — 결과 참고용으로만 사용', style: TextStyle(color: AppColors.gold, fontSize: 12)),
              ),
            ],
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
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(children: [
            _buildScoreRow('센터링', r['centeringScore'], r['centeringDetail'],
                sub: r['centeringRatio'] as String?, metric: 'centering'),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('코너', r['cornerScore'], r['cornerDetail'], metric: 'corner'),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('표면', r['surfaceScore'], r['surfaceDetail'], metric: 'surface'),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('화이트닝', r['whiteningScore'], r['whiteningDetail'], metric: 'whitening'),
          ]),
        ),
        const SizedBox(height: 24),
        if (widget.cardId != null) ...[
          OutlinedButton(
            onPressed: () async {
              if (!identityVerified && !await _showIdentityConsentDialog()) return;
              if (!mounted) return;
              _showGradeRegisterSheet(total, preselectedCardId: widget.cardId, preselectedCardName: widget.cardName);
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.gold),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_rounded, color: AppColors.gold, size: 18),
                SizedBox(width: 8),
                Text('앱 분석 결과 저장', style: TextStyle(color: AppColors.gold, fontSize: 15)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        ElevatedButton(
          onPressed: () => context.pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blue,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('돌아가기', style: TextStyle(color: Colors.white, fontSize: 15)),
        ),
      ],
    );
  }

  Future<bool> _showIdentityConsentDialog() async {
    final agreed = await AppConfirmDialog.show(
      context,
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.gold,
      title: '카드 미확인 안내',
      message:
          '이 사진은 스캐너가 등록된 카드와 일치하지 않거나 인식하지 못한 사진입니다.\n\n'
          '실제 카드와 다른 사진을 업로드하여 판매하는 행위는 사기에 해당하며, 민·형사상 법적 책임을 질 수 있습니다. 구매자 또는 관계 기관의 요청 시 판매자 정보 및 거래 내역이 제공될 수 있습니다.',
      cancelLabel: '취소',
      confirmLabel: '동의하고 계속',
      barrierDismissible: false,
    );
    return agreed == true;
  }

  void _showGradeRegisterSheet(double estimatedScore, {String? preselectedCardId, String? preselectedCardName}) {
    final appAnalysisId = _generateAppAnalysisId();
    final _searchCtrl = TextEditingController();
    Map<String, dynamic>? _selectedCard = preselectedCardId != null
        ? {'cardId': preselectedCardId, 'name': preselectedCardName ?? preselectedCardId, 'rarityCode': ''}
        : null;
    List<Map<String, dynamic>> _searchResults = [];
    bool _searching = false;
    String _selectedLanguage = 'KO';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> searchCards(String q) async {
            if (q.trim().isEmpty) {
              setModalState(() { _searchResults = []; _searching = false; });
              return;
            }
            setModalState(() => _searching = true);
            try {
              final res = await ApiClient.get('/api/cards/search', params: {'name': q.trim(), 'size': 10});
              final items = (res['data'] as Map?)?['content'] as List? ?? res['data'] as List? ?? [];
              setModalState(() {
                _searchResults = items.cast<Map<String, dynamic>>();
                _searching = false;
              });
            } catch (_) {
              setModalState(() => _searching = false);
            }
          }

          Future<void> submit() async {
            if (_selectedCard == null) return;
            final cardId = _selectedCard!['cardId'] as String?;
            if (cardId == null) return;
            final nav = Navigator.of(ctx);
            try {
              if (widget.assetId != null) {
                final files = <String, File>{
                  'front_image': await _resizePhoto(widget.photos[0]),
                  'back_image': await _resizePhoto(widget.photos[1]),
                };
                await ApiClient.postMultipart(
                  '${ApiConstants.assets}/${widget.assetId}/grading',
                  files: files,
                  fields: {
                    'cardStatus': 'RAW',
                    'app_analysis_id': appAnalysisId,
                    'estimated_grade': estimatedScore.toStringAsFixed(1),
                    'centering_score': _scoreField('centeringScore'),
                    'corner_score': _scoreField('cornerScore'),
                    'surface_score': _scoreField('surfaceScore'),
                    'whitening_score': _scoreField('whiteningScore'),
                    'centering_ratio': (_result?['centeringRatio'] as String?) ?? '',
                    'detection_confidence': _scoreField('detectionConfidence', fallback: 1.0, fractionDigits: 2),
                  },
                  sendTimeout: const Duration(seconds: 60),
                  receiveTimeout: const Duration(seconds: 60),
                );
                nav.pop();
                if (mounted) {
                  AppSuccessToast.show(context, '분석 결과가 저장됐습니다');
                  context.pop(true); // signal success back to capture screen → card detail
                }
                return;
              }

              String userId = 'guest';
              try {
                final userRes = await ApiClient.get('/api/users/me');
                userId = (userRes['data'] as Map<String, dynamic>?)?['userId'] as String? ?? 'guest';
              } catch (_) {}
              final createRes = await ApiClient.post(ApiConstants.assets, {
                'data': {
                  'userId': userId,
                  'cardId': cardId,
                  'quantity': 1,
                  'language': _selectedLanguage,
                  'cardStatus': 'RAW',
                  'certNumber': appAnalysisId,
                  'estimatedGrade': estimatedScore.toStringAsFixed(1),
                  'centeringScore': _scoreField('centeringScore'),
                  'cornerScore': _scoreField('cornerScore'),
                  'surfaceScore': _scoreField('surfaceScore'),
                  'whiteningScore': _scoreField('whiteningScore'),
                  'centeringRatio': (_result?['centeringRatio'] as String?) ?? '',
                  'detectionConfidence': _scoreField('detectionConfidence', fallback: 1.0, fractionDigits: 2),
                  'purchasedAt': DateTime.now().toIso8601String().substring(0, 10),
                }
              });
              final newAssetId = (createRes['data'] is Map)
                  ? ((createRes['data'] as Map)['assetId'] as String?)
                  : null;
              if (newAssetId != null && widget.photos.length >= 2) {
                final files = <String, File>{
                  'front_image': await _resizePhoto(widget.photos[0]),
                  'back_image': await _resizePhoto(widget.photos[1]),
                };
                await ApiClient.postMultipart(
                  '${ApiConstants.assets}/$newAssetId/grading',
                  files: files,
                  fields: {
                    'cardStatus': 'RAW',
                    'app_analysis_id': appAnalysisId,
                    'estimated_grade': estimatedScore.toStringAsFixed(1),
                    'centering_score': _scoreField('centeringScore'),
                    'corner_score': _scoreField('cornerScore'),
                    'surface_score': _scoreField('surfaceScore'),
                    'whitening_score': _scoreField('whiteningScore'),
                    'centering_ratio': (_result?['centeringRatio'] as String?) ?? '',
                    'detection_confidence': _scoreField('detectionConfidence', fallback: 1.0, fractionDigits: 2),
                  },
                  sendTimeout: const Duration(seconds: 60),
                  receiveTimeout: const Duration(seconds: 60),
                );
              }
              AssetNotifier.instance.notifyChanged();
              nav.pop();
              if (mounted) {
                AppSuccessToast.show(context, '분석 결과가 저장됐습니다');
              }
            } catch (e) {
              if (mounted) {
                AppErrorToast.show(context, '등록 실패: $e');
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  const Text('앱 분석 결과 저장', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('외부 등급사 인증 결과가 아닌 앱 예측 결과입니다.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 20),

                  // 언어 선택 — KO/JP/EN. 자산 가격은 선택한 언어 기준으로 계산됨.
                  if (widget.assetId == null) ...[
                    const Text('카드 언어', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: ['KO', 'JP', 'EN'].map((lang) {
                        final sel = _selectedLanguage == lang;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setModalState(() => _selectedLanguage = lang),
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
                  ],

                  // 카드 검색
                  const Text('카드 검색', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_selectedCard == null) ...[
                    TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '카드 이름 검색...',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        prefixIcon: _searching
                            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2)))
                            : const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.blue)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (v) => searchCards(v),
                    ),
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, __) => const Divider(color: AppColors.divider, height: 1),
                          itemBuilder: (_, i) {
                            final card = _searchResults[i];
                            return ListTile(
                              dense: true,
                              title: Text(card['name'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                              subtitle: Text(card['rarityCode'] ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              onTap: () => setModalState(() {
                                _selectedCard = card;
                                _searchResults = [];
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  ] else
                    GestureDetector(
                      onTap: () => setModalState(() { _selectedCard = null; _searchCtrl.clear(); }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.blue.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_selectedCard!['name'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                                Text(_selectedCard!['rarityCode'] ?? '', style: const TextStyle(color: AppColors.blue, fontSize: 12)),
                              ],
                            )),
                            const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
                  const Text('앱 분석 ID', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(appAnalysisId,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedCard != null ? submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        disabledBackgroundColor: AppColors.divider,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('앱 분석 결과 저장',
                          style: TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.bold)),
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

  String _scoreField(String key, {double fallback = 0.0, int fractionDigits = 1}) {
    return ((_result?[key] as num?)?.toDouble() ?? fallback).toStringAsFixed(fractionDigits);
  }

  String _generateAppAnalysisId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final suffix = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    return 'APP-$date-$suffix';
  }

  Widget _buildScoreRow(String label, dynamic scoreRaw, dynamic detail,
      {String? sub, String? metric}) {
    final score = (scoreRaw as num).toDouble();
    final color = score >= 9.0 ? AppColors.green : score >= 7.0 ? AppColors.blue : AppColors.red;
    final detailText = detail as String? ?? '';
    final reasons = metric != null ? _filterReasonsByMetric(metric) : <DeductionReason>[];
    final tappable = metric != null && reasons.isNotEmpty;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
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
          if (tappable) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ]),
        if (sub != null && sub.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 80),
            child: Text(sub, style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w500)),
          ),
        ],
        if (detailText.isNotEmpty) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 80),
            child: Text(detailText, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ),
        ],
        if (tappable) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 80),
            child: Text('${reasons.length}건 감점 사유 보기',
                style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );

    if (!tappable) return content;
    return InkWell(
      onTap: () => _showMetricDetailSheet(metric, label, score, color),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );
  }

  /// side/position → normalized Rect (이미지 위 대략 overlay).
  /// Day 3: backend bbox inverse transform 으로 정확화.
  Rect? _positionRect(String position) {
    switch (position) {
      case 'top_left':     return const Rect.fromLTWH(0.02, 0.02, 0.35, 0.25);
      case 'top_right':    return const Rect.fromLTWH(0.63, 0.02, 0.35, 0.25);
      case 'bottom_left':  return const Rect.fromLTWH(0.02, 0.73, 0.35, 0.25);
      case 'bottom_right': return const Rect.fromLTWH(0.63, 0.73, 0.35, 0.25);
      case 'center':       return const Rect.fromLTWH(0.30, 0.40, 0.40, 0.20);
      case 'center_left':  return const Rect.fromLTWH(0.02, 0.40, 0.35, 0.20);
      case 'middle_right': return const Rect.fromLTWH(0.63, 0.40, 0.35, 0.20);
      default: return null;
    }
  }

  /// side → photo File index. front=0, back=1.
  File? _photoForSide(String side) {
    if (side == 'front' && widget.photos.isNotEmpty) return widget.photos[0];
    if (side == 'back' && widget.photos.length > 1) return widget.photos[1];
    return null;
  }

  /// side + position 그룹핑 (예: "앞면 좌상단 코너 마모 후보 2건").
  Map<String, List<DeductionReason>> _groupBySidePosition(List<DeductionReason> reasons) {
    final groups = <String, List<DeductionReason>>{};
    for (final r in reasons) {
      final key = '${r.side}|${r.position}|${r.type}';
      groups.putIfAbsent(key, () => []).add(r);
    }
    return groups;
  }

  List<DeductionReason> _filterReasonsByMetric(String metric) {
    final p = _parsed;
    if (p == null) return const [];
    bool match(DeductionReason r) {
      switch (metric) {
        case 'centering': return r.type == 'centering';
        case 'corner':    return r.type == 'corner';
        case 'surface':   return r.type == 'surface' || r.type == 'scratch' || r.type == 'dent';
        case 'whitening': return r.type == 'whitening';
        case 'edge':      return r.type == 'edge';
        default: return false;
      }
    }
    final list = p.deductionReasons.where(match).toList()
      ..sort((a, b) {
        final ap = a.penalty.abs();
        final bp = b.penalty.abs();
        if (ap != bp) return bp.compareTo(ap);
        return b.confidence.compareTo(a.confidence);
      });
    return list;
  }

  void _showMetricDetailSheet(String metric, String label, double score, Color color) {
    final reasons = _filterReasonsByMetric(metric);
    final totalPenalty = reasons.fold<double>(0, (s, r) => s + r.penalty);
    final avgConfidence = reasons.isEmpty
        ? 0.0
        : reasons.fold<double>(0, (s, r) => s + r.confidence) / reasons.length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) {
            return Column(children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(score.toStringAsFixed(1),
                      style: TextStyle(
                          color: color, fontSize: 22, fontWeight: FontWeight.bold)),
                  const Text(' / 10',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(children: [
                    Expanded(child: _summaryItem('감점 항목', '${reasons.length}건')),
                    Container(width: 1, height: 24, color: AppColors.divider),
                    Expanded(child: _summaryItem('총 감점', '${totalPenalty.toStringAsFixed(1)}점')),
                    Container(width: 1, height: 24, color: AppColors.divider),
                    Expanded(child: _summaryItem('평균 신뢰도', '${(avgConfidence * 100).round()}%')),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: reasons.isEmpty
                    ? const Center(
                        child: Text('감지된 감점 사유가 없어요',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      )
                    : ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          _buildMetricImageSection(metric, reasons),
                          const SizedBox(height: 16),
                          _buildGroupSummary(reasons),
                          const SizedBox(height: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text('세부 감점 사유',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                          ...reasons.asMap().entries.map((e) {
                            final i = e.key;
                            final r = e.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.blue.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text('${i + 1}',
                                      style: const TextStyle(
                                          color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_humanReasonLabel(r),
                                          style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                      if (r.explanation.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(r.explanation,
                                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                            maxLines: 2, overflow: TextOverflow.ellipsis),
                                      ],
                                      const SizedBox(height: 2),
                                      Text(
                                        '-${r.penalty.toStringAsFixed(1)}점 · 신뢰도 ${(r.confidence * 100).round()}%',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                _severityChip(r.severity),
                              ]),
                            );
                          }),
                        ],
                      ),
              ),
            ]);
          },
        );
      },
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(children: [
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      const SizedBox(height: 4),
      Text(value,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildMetricImageSection(String metric, List<DeductionReason> reasons) {
    if (metric == 'centering') return _buildCenteringVisual();
    final frontReasons = reasons.where((r) => r.side == 'front').toList();
    final backReasons = reasons.where((r) => r.side == 'back').toList();
    final showFront = metric != 'whitening';
    return Row(children: [
      if (showFront) ...[
        Expanded(child: _buildPhotoWithBoxes('앞면', _photoForSide('front'), frontReasons)),
        const SizedBox(width: 10),
      ],
      Expanded(child: _buildPhotoWithBoxes('뒷면', _photoForSide('back'), backReasons)),
    ]);
  }

  Widget _buildPhotoWithBoxes(String label, File? file, List<DeductionReason> reasons) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 63.0 / 88.0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LayoutBuilder(
              builder: (_, c) {
                final exists = file != null && file.existsSync();
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (exists)
                      Image.file(file, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: AppColors.divider))
                    else
                      Container(color: AppColors.divider),
                    ...reasons.where((r) => _positionRect(r.position) != null).map((r) {
                      final rect = _positionRect(r.position)!;
                      final c2 = _severityColor(r.severity);
                      return Positioned(
                        left: rect.left * c.maxWidth,
                        top: rect.top * c.maxHeight,
                        width: rect.width * c.maxWidth,
                        height: rect.height * c.maxHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            color: c2.withValues(alpha: 0.22),
                            border: Border.all(color: c2, width: 2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('${reasons.length}건',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
      ],
    );
  }

  Widget _buildCenteringVisual() {
    final p = _parsed;
    final front = _photoForSide('front');
    final ratio = p?.centeringRatio ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(
        aspectRatio: 63.0 / 88.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LayoutBuilder(
            builder: (_, c) {
              final exists = front != null && front.existsSync();
              return Stack(fit: StackFit.expand, children: [
                if (exists)
                  Image.file(front, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(color: AppColors.divider))
                else
                  Container(color: AppColors.divider),
                Positioned(
                  left: c.maxWidth / 2 - 1, top: 0, bottom: 0,
                  child: Container(width: 2, color: AppColors.blue.withValues(alpha: 0.6)),
                ),
                Positioned(
                  top: c.maxHeight / 2 - 1, left: 0, right: 0,
                  child: Container(height: 2, color: AppColors.blue.withValues(alpha: 0.6)),
                ),
              ]);
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (ratio.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(ratio,
              style: const TextStyle(
                  color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
    ]);
  }

  Widget _buildGroupSummary(List<DeductionReason> reasons) {
    final groups = _groupBySidePosition(reasons);
    if (groups.isEmpty) return const SizedBox.shrink();
    final entries = groups.entries.toList()
      ..sort((a, b) {
        final aPenalty = a.value.fold<double>(0, (s, r) => s + r.penalty.abs());
        final bPenalty = b.value.fold<double>(0, (s, r) => s + r.penalty.abs());
        return bPenalty.compareTo(aPenalty);
      });
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('영역별 요약',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...entries.take(5).map((e) {
          final list = e.value;
          final first = list.first;
          final loc = [_sideKo[first.side] ?? '', _positionKo[first.position] ?? '']
              .where((s) => s.isNotEmpty).join(' ');
          final type = _typeKo[first.type] ?? first.type;
          final total = list.fold<double>(0, (s, r) => s + r.penalty);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: _severityColor(first.severity),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.isNotEmpty ? '$loc $type · ${list.length}건' : '$type · ${list.length}건',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
              Text('-${total.abs().toStringAsFixed(1)}점',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
      ]),
    );
  }
}
