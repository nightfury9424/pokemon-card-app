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

class GradingResultScreen extends StatefulWidget {
  final List<File> photos;
  final String? assetId;
  final String? cardId;
  final String? cardName;
  const GradingResultScreen({super.key, required this.photos, this.assetId, this.cardId, this.cardName});
  @override
  State<GradingResultScreen> createState() => _GradingResultScreenState();
}

class _GradingResultScreenState extends State<GradingResultScreen> {
  Map<String, dynamic>? _result;
  bool _loading = true;
  String? _error;

  static const _photoKeys = ['front_image', 'back_image'];

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
      final res = await ApiClient.postMultipart(
        ApiConstants.gradingAnalyze,
        files: files,
        fields: {
          'userId': userId,
          if (widget.cardId != null) 'cardId': widget.cardId!,
        },
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 120),
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
              : _buildResult(),
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(children: [
            _buildScoreRow('센터링', r['centeringScore'], r['centeringDetail'],
                sub: r['centeringRatio'] as String?),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('코너', r['cornerScore'], r['cornerDetail']),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('표면', r['surfaceScore'], r['surfaceDetail']),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('화이트닝', r['whiteningScore'], r['whiteningDetail']),
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
              await ApiClient.post(ApiConstants.assets, {
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

  Widget _buildScoreRow(String label, dynamic scoreRaw, dynamic detail, {String? sub}) {
    final score = (scoreRaw as num).toDouble();
    final color = score >= 9.0 ? AppColors.green : score >= 7.0 ? AppColors.blue : AppColors.red;
    final detailText = detail as String? ?? '';
    return Column(
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
      ],
    );
  }
}
