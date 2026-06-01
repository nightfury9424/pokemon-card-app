import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import '../../core/network/api_client.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/constants/api_constants.dart';
import '../../core/notifiers/asset_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_segmented_toggle.dart';
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
  // P0-1 Codex 사후 fix: image aspect 동적 측정 (AspectRatio 가정 X).
  // P0-fix-1: front + back 각각 측정 (back overlay aspect mismatch 방지).
  double? _frontImageAspect;
  double? _backImageAspect;
  // P0-C: surface/whitening 토글 view index (0=원본, 1=후보 강조, 2=후보 위치).
  final Map<String, int> _evidenceViewIndex = {'surface': 0, 'whitening': 0};
  // hotfix 9: evidence preload cache — 결과 화면 진입 시 6 image 미리 fetch.
  // 사용자가 토글 누를 때 즉시 표시 (re-fetch X).
  final Map<String, Future<List<int>?>> _evidenceCache = {};

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
        _loadImageAspect('front');
        _loadImageAspect('back');
        // hotfix 9: evidence 6 image preload (병렬 background)
        _preloadEvidence();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // hotfix 9: evidence 6 image (warped + CLAHE + mask × front/back) 미리 fetch.
  // 사용자 결과 화면 토글 클릭 시 즉시 표시 (네트워크 wait X).
  void _preloadEvidence() {
    final sessionId = _parsed?.extra?['evidence_session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    const layers = [
      'front_original', 'back_original',
      'front_surface', 'back_surface',
      'front_whitening', 'back_whitening',
    ];
    for (final layer in layers) {
      final url = '${ApiConstants.baseUrl}${ApiConstants.gradingEvidence(sessionId, layer)}';
      _evidenceCache.putIfAbsent(url, () => ApiClient.downloadBytes(url));
    }
  }

  // P0-fix-1: front + back 각각 aspect 측정 → AspectRatio 동적.
  void _loadImageAspect(String side) {
    final file = _photoForSide(side);
    if (file == null || !file.existsSync()) return;
    final provider = FileImage(file);
    final stream = provider.resolve(const ImageConfiguration());
    ImageStreamListener? listener;
    listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() {
          final aspect = info.image.width / info.image.height;
          if (side == 'front') {
            _frontImageAspect = aspect;
          } else {
            _backImageAspect = aspect;
          }
        });
      }
      if (listener != null) stream.removeListener(listener);
    }, onError: (_, _) {
      if (listener != null) stream.removeListener(listener);
    });
    stream.addListener(listener);
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
              // P0-1: 강등 배지 + 사유 (grade_decision_trace.caps_applied)
              ..._buildGradeDemotion(p),
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

  // P0-1: grade_decision_trace.caps_applied 가 있으면 강등 배지 + 사유 메시지.
  List<Widget> _buildGradeDemotion(GradingResult p) {
    final trace = p.gradeDecisionTrace;
    if (trace == null) return const [];
    final caps = trace['caps_applied'];
    if (caps is! List || caps.isEmpty) return const [];
    final first = caps.first;
    final message = first is Map ? (first['message']?.toString() ?? '') : '';
    final rawGrade = trace['raw_grade_by_weight']?.toString() ?? '';
    return [
      const SizedBox(height: 6),
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFE67E22).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE67E22), width: 1),
          ),
          child: const Text('강등',
              style: TextStyle(
                  color: Color(0xFFE67E22), fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        if (rawGrade.isNotEmpty)
          Text('가중 $rawGrade → 최종 ${p.grade}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
      if (message.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(message,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    ];
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
        : '더 정확한 분석을 원하면 다시 촬영해 주세요';
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
    final identityVerified = (r['identityVerified'] as bool?) ?? (r['identity_verified'] as bool?) ?? true;

    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32),
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
              child: const Text('PokeFolio AI 컨디션 분석',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            const Text('예상 컨디션 점수', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(total.toStringAsFixed(1),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 56, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              '실물 카드 상태를 바탕으로 한 참고용 분석입니다',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
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
                // 기존 그레이딩 결과 확인 — 자동 덮어쓰기 금지.
                try {
                  final assetRes = await ApiClient.get(
                      '${ApiConstants.assets}/${widget.assetId}');
                  final assetData = assetRes['data'] as Map<String, dynamic>?;
                  final existingGrade =
                      (assetData?['estimatedGrade'] as num?)?.toDouble();
                  if (existingGrade != null && mounted) {
                    final confirmed = await AppConfirmDialog.show(
                      context,
                      icon: Icons.compare_arrows_rounded,
                      iconColor: AppColors.blue,
                      title: '기존 분석 결과가 있어요',
                      message:
                          '기존 분석: ${existingGrade.toStringAsFixed(1)}점\n'
                          '새 분석: ${estimatedScore.toStringAsFixed(1)}점\n\n'
                          '새 결과로 변경하면 기존 결과는 사라져요.',
                      cancelLabel: '기존 유지',
                      confirmLabel: '새 결과로 변경',
                    );
                    if (confirmed != true) {
                      if (mounted) {
                        AppInfoToast.show(context, '기존 결과를 유지했어요');
                      }
                      return;
                    }
                  }
                } catch (_) {
                  // fetch 실패 시 그대로 진행 (silent, 안전성 우선)
                }

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
    // hotfix 8: row tappable = metric 만 있으면 항상 (reasons empty 라도 sheet 진입).
    // 코너/화이트닝 만점 (reasons 0건) 시 chevron X / tap X 됐던 bug fix.
    final tappable = metric != null;
    final hasReasons = reasons.isNotEmpty;

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
            // hotfix 8: confidence < 0.50 = 참고 후보 (penalty 0). "감점 사유" 표현 X.
            // 진짜 감점 (penalty > 0) 개수와 참고 후보 개수 분리 또는 "후보 상세 보기" 통합 표현.
            child: Text(
              hasReasons ? '${reasons.length}건 후보 상세 보기' : '상세 보기',
              style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w600),
            ),
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

  // hotfix 9: allReasons / visibleReasons 분리.
  //   allReasons = backend 의 모든 후보 (debug/내부 분석 보존)
  //   visibleReasons = penalty > 0 만 (사용자 화면 노출)
  //   centering 은 점수 source 분리 안 됨 → 그대로 표시
  List<DeductionReason> _filterReasonsByMetric(String metric) {
    final all = _allReasonsByMetric(metric);
    // hotfix 9: 사용자 화면 = penalty > 0 만 (centering 예외 — 단일 후보이고 점수 직접)
    if (metric == 'centering') return all;
    return all.where((r) => r.penalty > 0).toList();
  }

  // hotfix 9: 내부 debug / preload 등에 필요한 전체 reasons.
  List<DeductionReason> _allReasonsByMetric(String metric) {
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
    final list = p.deductionReasons
        .where(match)
        .where((r) => r.confidence >= 0.15 || r.type == 'centering')
        .toList()
      ..sort((a, b) {
        final ap = a.penalty.abs();
        final bp = b.penalty.abs();
        if (ap != bp) return bp.compareTo(ap);
        return b.confidence.compareTo(a.confidence);
      });
    final cap = (metric == 'surface' || metric == 'scratch') ? 10 : 20;
    return list.length > cap ? list.sublist(0, cap) : list;
  }

  void _showMetricDetailSheet(String metric, String label, double score, Color color) {
    // hotfix 9: visible = penalty>0 만 (centering 예외 = centering 자체 점수 source).
    // 참고 후보 (penalty=0) 는 사용자 화면 노출 X (debug 보관은 _allReasonsByMetric).
    final reasons = _filterReasonsByMetric(metric);
    final scoredReasons = reasons.where((r) => r.penalty > 0).toList();
    final totalPenalty = scoredReasons.fold<double>(0, (s, r) => s + r.penalty);

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
            // P0-C hotfix issue 2: StatefulBuilder — outer setState 가 sheet rebuild 시키지 못하던
            // bug fix. innerSetState 호출 시 sheet 안의 widget tree 만 rebuild.
            return StatefulBuilder(
              builder: (sheetContext, sheetSetState) {
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
                  // hotfix 9: 평균 신뢰도 % 제거. 사용자 화면 = 감점 후보 / 총 감점 만.
                  // 디버그 metric (신뢰도 33%) 같은 숫자 노출 X.
                  child: Row(children: [
                    Expanded(child: _summaryItem(
                      '감점 후보',
                      scoredReasons.isEmpty ? '0건' : '${scoredReasons.length}건')),
                    Container(width: 1, height: 24, color: AppColors.divider),
                    Expanded(child: _summaryItem('총 감점',
                      totalPenalty > 0
                          ? '${totalPenalty.toStringAsFixed(1)}점'
                          : '없음')),
                    Container(width: 1, height: 24, color: AppColors.divider),
                    // 사용자 친화 안내 — 숫자 신뢰도 대신 분석 성격 안내
                    Expanded(child: _summaryItem('분석 안내', '참고용')),
                  ]),
                ),
              ),
              // hotfix 9: "신뢰도 낮은 참고 후보 X건 숨김" 안내 제거.
              // 사용자 화면 = 실제 감점 후보만 보여줌 (참고/신뢰도 노출 X).
              const SizedBox(height: 12),
              Expanded(
                // hotfix 9 보정: empty state 가 이미지 영역 대체 X.
                // visible=0 (감점 0건) 라도 항상 이미지/토글 표시. "없습니다" 는 그 아래.
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    _buildMetricImageSection(metric, reasons, sheetSetState),
                    const SizedBox(height: 16),
                    if (reasons.isEmpty) ...[
                      // visible 0건 = 감점 후보 없음. 이미지 영역은 위에서 보임.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.divider),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '감지된 감점 후보가 없습니다',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ),
                    ] else ...[
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
                                      // hotfix 9: 신뢰도 % 사용자 화면 노출 X. 감점만 표시.
                                      // (참고 후보 = visibleReasons 에서 제외 — 여기 도달 X)
                                      Text(
                                        '-${r.penalty.toStringAsFixed(1)}점',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                _severityChip(r.severity),
                              ]),
                            );
                          }),
                    ],  // hotfix 9: else 분기 닫기 (reasons.isNotEmpty)
                  ],    // ListView children 닫기
                ),     // ListView 닫기
              ),       // Expanded 닫기
            ]);
              },  // StatefulBuilder builder 닫기
            );
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

  // P0-C hotfix issue 2: sheetSetState 받음 — 토글 onChanged 가 sheet 내부 rebuild.
  Widget _buildMetricImageSection(String metric, List<DeductionReason> reasons,
      [StateSetter? sheetSetState]) {
    if (metric == 'centering') return _buildCenteringVisual();
    if (metric == 'corner') return _buildCornerEvidence(reasons);
    final frontReasons = reasons.where((r) => r.side == 'front').toList();
    final backReasons = reasons.where((r) => r.side == 'back').toList();
    final showFront = metric != 'whitening';
    // P0-C: 토글 (원본 / 후보 강조 / 후보 위치) + evidence view.
    final viewIdx = _evidenceViewIndex[metric] ?? 0;
    final sessionId = _parsed?.extra?['evidence_session_id']?.toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (sessionId != null && sessionId.isNotEmpty) ...[
        AppSegmentedToggle(
          labels: const ['원본 보기', '후보 강조 보기', '후보 위치 표시'],
          selectedIndex: viewIdx,
          // P0-C hotfix issue 2: outer setState + sheetSetState 둘 다 → sheet rebuild
          onChanged: (i) {
            setState(() => _evidenceViewIndex[metric] = i);
            if (sheetSetState != null) sheetSetState(() {});
          },
        ),
        const SizedBox(height: 10),
      ],
      Row(children: [
        if (showFront) ...[
          Expanded(child: _buildEvidenceImage(metric, 'front', frontReasons, viewIdx, sessionId)),
          const SizedBox(width: 10),
        ],
        Expanded(child: _buildEvidenceImage(metric, 'back', backReasons, viewIdx, sessionId)),
      ]),
      const SizedBox(height: 8),
      _buildAnalysisBasisLabel(metric, viewIdx),
    ]);
  }

  // P0-C: 토글 index 기반 evidence image (원본/강조/위치) — side 별.
  Widget _buildEvidenceImage(String metric, String side, List<DeductionReason> reasons,
      int viewIdx, String? sessionId) {
    if (viewIdx == 2 || sessionId == null || sessionId.isEmpty) {
      // 후보 위치 표시 = 기존 원본 + bbox overlay (P0-fix-1)
      return _buildPhotoWithBoxes(side == 'front' ? '앞면' : '뒷면', side, reasons);
    }
    // 원본/강조 = backend evidence URL fetch (hotfix 9: preload cache 사용 — 즉시 표시)
    final layerName = viewIdx == 0
        ? '${side}_original'
        : '${side}_$metric';   // ${side}_surface or ${side}_whitening
    final url = '${ApiConstants.baseUrl}${ApiConstants.gradingEvidence(sessionId, layerName)}';
    final aspect = (side == 'front' ? _frontImageAspect : _backImageAspect) ?? 3.0 / 4.0;
    final future = _evidenceCache.putIfAbsent(url, () => ApiClient.downloadBytes(url));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: aspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FutureBuilder<List<int>?>(
              future: future,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  // hotfix 9: 로딩 명확 표시
                  return Container(
                    color: AppColors.bg,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: const [
                      SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(AppColors.textMuted))),
                      SizedBox(height: 8),
                      Text('분석 이미지를 불러오는 중입니다',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          textAlign: TextAlign.center),
                    ]),
                  );
                }
                final bytes = snap.data;
                if (bytes == null || bytes.isEmpty) {
                  // hotfix 9: 실패 명확 (조용히 원본 X)
                  return Container(
                    color: AppColors.bg,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.image_not_supported_outlined,
                          color: AppColors.textMuted, size: 24),
                      SizedBox(height: 6),
                      Text('분석 이미지를 불러오지 못했습니다',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          textAlign: TextAlign.center),
                    ]),
                  );
                }
                return Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text(side == 'front' ? '앞면' : '뒷면',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('${reasons.length}건',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ]),
      ],
    );
  }

  // P0-C: 토글 view 별 자연어 설명 (사용자 친화 — 기술명 노출 X).
  Widget _buildAnalysisBasisLabel(String metric, int viewIdx) {
    String? text;
    if (metric == 'surface') {
      text = switch (viewIdx) {
        0 => '카드 표면을 그대로 보여줍니다.',
        1 => '표면의 얇은 선형·점형 패턴 후보를 강조했습니다.',
        2 => '후보로 감지된 위치를 표시했습니다.',
        _ => null,
      };
    } else if (metric == 'whitening') {
      text = switch (viewIdx) {
        0 => '카드 뒷면을 그대로 보여줍니다.',
        1 => '테두리 주변의 밝기와 색 빠짐 후보를 강조했습니다.',
        2 => '후보로 감지된 위치를 표시했습니다.',
        _ => null,
      };
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(children: [
        const Icon(Icons.science_outlined, size: 12, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ),
      ]),
    );
  }

  // P0-fix-1: side 별 cardBbox + aspect + source 확인.
  // 정책: source != "detected" → overlay 숨김 + 안내 (잘못된 박스 X).
  Widget _buildPhotoWithBoxes(String label, String side, List<DeductionReason> reasons) {
    final file = _photoForSide(side);
    final p = _parsed;
    final cardBboxAny = p?.cardBbox?[side];
    final isDetected = cardBboxAny?['source']?.toString() == 'detected';
    final cardBboxDouble = isDetected ? _toDoubleMap(cardBboxAny) : null;
    final aspect = (side == 'front' ? _frontImageAspect : _backImageAspect) ?? 3.0 / 4.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: file != null && file.existsSync()
              ? () => _openFullscreenImage(file)
              : null,
          child: AspectRatio(
            aspectRatio: aspect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LayoutBuilder(
                builder: (_, c) {
                  return Stack(fit: StackFit.expand, children: [
                    if (file != null && file.existsSync())
                      Image.file(file, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(color: AppColors.divider))
                    else
                      Container(color: AppColors.divider),
                    if (cardBboxDouble != null && reasons.isNotEmpty)
                      CustomPaint(
                        size: Size(c.maxWidth, c.maxHeight),
                        painter: _ReasonBboxPainter(
                          reasons: reasons,
                          cardBbox: cardBboxDouble,
                        ),
                      ),
                  ]);
                },
              ),
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
        // P0-fix-1: fallback 시 안내 — 잘못된 박스 X 보장
        if (!isDetected && reasons.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text('카드 외곽 검출 불안정 — 위치 표시 숨김',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ],
      ],
    );
  }

  // P0-fix-1: cardBbox dynamic → double Map (painter 가 double 만 받음).
  Map<String, double>? _toDoubleMap(Map<String, dynamic>? src) {
    if (src == null) return null;
    final out = <String, double>{};
    for (final entry in src.entries) {
      final v = entry.value;
      if (v is num) out[entry.key] = v.toDouble();
    }
    return out;
  }

  // P0-1: corner sheet empty 상태에서도 4 corner crop + 점수 시각화.
  Widget _buildCornerEvidence(List<DeductionReason> reasons) {
    final p = _parsed;
    // P0-fix-1: cornerRegions = {"front":{4}, "back":{4}}. 일단 front 만 표시 (기존 UX).
    // cardBbox['front'].source != "detected" 이면 corner overlay 도 부정확 → 숨김
    final cardBboxAny = p?.cardBbox?['front'];
    final bboxDetected = cardBboxAny?['source']?.toString() == 'detected';
    final regions = bboxDetected ? (p?.cornerRegions?['front']) : null;
    final front = _photoForSide('front');
    if (regions == null || front == null || !front.existsSync()) {
      // P0-fix-1: detect 실패 시 corner crop X (잘못된 위치 박스 방지)
      final msg = !bboxDetected
          ? '카드 외곽 검출 불안정 — 코너 영역 표시 숨김'
          : (reasons.isEmpty
              ? '4개 코너 모두 검사 — 감점 없음'
              : '코너 영역 분석 정보 없음');
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(msg,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            textAlign: TextAlign.center),
      );
    }
    final labels = ['좌상', '우상', '좌하', '우하'];
    final keys = ['top_left', 'top_right', 'bottom_left', 'bottom_right'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('앞면 4개 코너',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(children: List.generate(4, (i) {
        final r = regions[keys[i]];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
            child: GestureDetector(
              onTap: () => _openFullscreenImage(front),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LayoutBuilder(
                    builder: (_, c) {
                      return Stack(fit: StackFit.expand, children: [
                        if (r != null)
                          _CornerCropPainter(file: front, region: r)
                        else
                          Container(color: AppColors.divider),
                        Positioned(
                          left: 4, bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(labels[i],
                                style: const TextStyle(color: Colors.white, fontSize: 9)),
                          ),
                        ),
                      ]);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      })),
      const SizedBox(height: 8),
      Text(
        reasons.isEmpty
            ? '4개 코너 모두 검사 완료 — 감점 없음'
            : '${reasons.length}건 후보 감지',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
      ),
    ]);
  }

  // P0-1: card_bbox + centering_lines + confidence 기반 evidence overlay.
  // 사진 박스 정중앙 X — 실제 카드 외곽 + 검출된 inner border 4 line 그리기.
  Widget _buildCenteringVisual() {
    final p = _parsed;
    final front = _photoForSide('front');
    final ratio = p?.centeringRatio ?? '';
    // P0-fix-1: cardBbox source != "detected" → 외곽선/lines 숨김 + 추정 배지
    final cardBboxAny = p?.cardBbox?['front'];
    final bboxDetected = cardBboxAny?['source']?.toString() == 'detected';
    final cardBbox = bboxDetected ? _toDoubleMap(cardBboxAny) : null;
    final lines = p?.centeringLines;
    final conf = p?.centeringConfidence ?? 0.0;
    final source = p?.centeringSource ?? 'fallback';
    final lowConf = conf < 0.5 || source == 'fallback' || !bboxDetected;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: front != null && front.existsSync()
            ? () => _openFullscreenImage(front)
            : null,
        child: AspectRatio(
          aspectRatio: _frontImageAspect ?? 3.0 / 4.0,
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
                  if (cardBbox != null)
                    CustomPaint(
                      size: Size(c.maxWidth, c.maxHeight),
                      painter: _CenteringEvidencePainter(
                        cardBbox: cardBbox,
                        lines: lines,
                        lowConfidence: lowConf,
                      ),
                    ),
                ]);
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
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
        const SizedBox(width: 6),
        if (lowConf)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFFC107), width: 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 11, color: Color(0xFFFFC107)),
              const SizedBox(width: 3),
              Text('추정 (신뢰도 ${(conf * 100).round()}%)',
                  style: const TextStyle(
                      color: Color(0xFFFFC107), fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    ]);
  }

  void _openFullscreenImage(File file) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullscreenImageViewer(file: file),
      fullscreenDialog: true,
    ));
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
          // hotfix 8 보정: 감점 / 참고 분리. penalty 0 후보 = 점수 영향 X.
          final scored = list.where((r) => r.penalty > 0).toList();
          final reference = list.where((r) => r.penalty == 0).toList();
          final scoredPenalty = scored.fold<double>(0, (s, r) => s + r.penalty);
          // 카운트 표시: 감점 N건 (+ 참고 M건)
          final countLabel = scored.isNotEmpty && reference.isNotEmpty
              ? '감점 ${scored.length}건 · 참고 ${reference.length}건'
              : scored.isNotEmpty
                  ? '감점 ${scored.length}건'
                  : '참고 ${reference.length}건';
          // 점수 표시: 감점 있음 = "-X.X점", 없음 = "점수 영향 없음"
          final rightLabel = scoredPenalty > 0
              ? '-${scoredPenalty.toStringAsFixed(1)}점'
              : '점수 영향 없음';
          // severity 색: 실제 감점 후보 우선, 없으면 참고 후보 색 (옅음)
          final severityForColor = scored.isNotEmpty ? scored.first.severity : first.severity;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: scored.isNotEmpty
                      ? _severityColor(severityForColor)
                      : AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.isNotEmpty ? '$loc $type · $countLabel' : '$type · $countLabel',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
              Text(rightLabel,
                  style: TextStyle(
                      color: scoredPenalty > 0 ? AppColors.textSecondary : AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          );
        }),
      ]),
    );
  }
}

// === P0-1 evidence layer widgets ===

/// 사진 위에 card_bbox 외곽 + centering_lines 4 line 그리기.
/// low confidence 면 dashed line.
class _CenteringEvidencePainter extends CustomPainter {
  final Map<String, double> cardBbox;
  final Map<String, double>? lines;
  final bool lowConfidence;

  _CenteringEvidencePainter({
    required this.cardBbox,
    required this.lines,
    required this.lowConfidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = cardBbox['x']! * size.width;
    final cy = cardBbox['y']! * size.height;
    final cw = cardBbox['w']! * size.width;
    final ch = cardBbox['h']! * size.height;

    // 카드 외곽
    final bboxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF3498DB).withValues(alpha: 0.7);
    canvas.drawRect(Rect.fromLTWH(cx, cy, cw, ch), bboxPaint);

    if (lines == null) return;
    final lx = cardBbox['x']! + (lines!['left_x'] ?? 0) * cardBbox['w']!;
    final rx = cardBbox['x']! + (lines!['right_x'] ?? 1) * cardBbox['w']!;
    final ty = cardBbox['y']! + (lines!['top_y'] ?? 0) * cardBbox['h']!;
    final by = cardBbox['y']! + (lines!['bottom_y'] ?? 1) * cardBbox['h']!;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = lowConfidence
          ? const Color(0xFFFFC107).withValues(alpha: 0.85)
          : const Color(0xFF3498DB).withValues(alpha: 0.85);

    if (lowConfidence) {
      _drawDashedLine(canvas, Offset(lx * size.width, cy), Offset(lx * size.width, cy + ch), linePaint);
      _drawDashedLine(canvas, Offset(rx * size.width, cy), Offset(rx * size.width, cy + ch), linePaint);
      _drawDashedLine(canvas, Offset(cx, ty * size.height), Offset(cx + cw, ty * size.height), linePaint);
      _drawDashedLine(canvas, Offset(cx, by * size.height), Offset(cx + cw, by * size.height), linePaint);
    } else {
      canvas.drawLine(Offset(lx * size.width, cy), Offset(lx * size.width, cy + ch), linePaint);
      canvas.drawLine(Offset(rx * size.width, cy), Offset(rx * size.width, cy + ch), linePaint);
      canvas.drawLine(Offset(cx, ty * size.height), Offset(cx + cw, ty * size.height), linePaint);
      canvas.drawLine(Offset(cx, by * size.height), Offset(cx + cw, by * size.height), linePaint);
    }
  }

  void _drawDashedLine(Canvas c, Offset a, Offset b, Paint p) {
    const dashW = 6.0;
    const gapW = 4.0;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final n = (dist / (dashW + gapW)).floor();
    final ux = dx / dist;
    final uy = dy / dist;
    for (int i = 0; i < n; i++) {
      final s = i * (dashW + gapW);
      c.drawLine(Offset(a.dx + ux * s, a.dy + uy * s),
          Offset(a.dx + ux * (s + dashW), a.dy + uy * (s + dashW)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _CenteringEvidencePainter old) =>
      old.cardBbox != cardBbox || old.lines != lines || old.lowConfidence != lowConfidence;
}

/// 사진 위에 reason.bbox 그리기 (severity 색).
/// reason.bbox = warped 카드 좌표 (0~1) → cardBbox 로 사진 좌표 변환.
class _ReasonBboxPainter extends CustomPainter {
  final List<DeductionReason> reasons;
  final Map<String, double> cardBbox;

  _ReasonBboxPainter({required this.reasons, required this.cardBbox});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = cardBbox['x']! * size.width;
    final cy = cardBbox['y']! * size.height;
    final cw = cardBbox['w']! * size.width;
    final ch = cardBbox['h']! * size.height;
    for (final r in reasons) {
      final b = r.bbox;
      if (b == null || b.length < 4) continue;
      final color = _severityColor(r.severity).withValues(alpha: 0.85);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color;
      final rect = Rect.fromLTWH(
        cx + b[0] * cw,
        cy + b[1] * ch,
        b[2] * cw,
        b[3] * ch,
      );
      canvas.drawRect(rect, paint);
    }
  }

  Color _severityColor(String sev) {
    switch (sev) {
      case 'major':
        return const Color(0xFFE74C3C);
      case 'moderate':
        return const Color(0xFFE67E22);
      default:
        return const Color(0xFFF1C40F);
    }
  }

  @override
  bool shouldRepaint(covariant _ReasonBboxPainter old) =>
      old.reasons != reasons || old.cardBbox != cardBbox;
}

/// 사진의 region 영역만 1:1 box 에 채워서 표시 (OverflowBox + Transform).
class _CornerCropPainter extends StatelessWidget {
  final File file;
  final Map<String, double> region;
  const _CornerCropPainter({required this.file, required this.region});

  @override
  Widget build(BuildContext context) {
    final w = region['w'] ?? 0;
    final h = region['h'] ?? 0;
    if (w <= 0 || h <= 0) return Container(color: const Color(0xFF333333));
    return LayoutBuilder(builder: (_, c) {
      final fullW = c.maxWidth / w;
      final fullH = c.maxHeight / h;
      return ClipRect(
        child: OverflowBox(
          maxWidth: fullW,
          maxHeight: fullH,
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(-(region['x'] ?? 0) * fullW, -(region['y'] ?? 0) * fullH),
            child: SizedBox(
              width: fullW,
              height: fullH,
              child: Image.file(file, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: const Color(0xFF333333))),
            ),
          ),
        ),
      );
    });
  }
}

/// fullscreen image viewer (pinch zoom + pan + 닫기).
class _FullscreenImageViewer extends StatelessWidget {
  final File file;
  const _FullscreenImageViewer({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4.0,
            child: Image.file(file,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.error, color: Colors.white))),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ]),
    );
  }
}
