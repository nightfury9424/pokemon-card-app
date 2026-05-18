import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/notifiers/asset_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/price_display_policy.dart';
import '../../core/widgets/card_image.dart';

class ScannerScreen extends StatefulWidget {
  /// 카드 상세에서 진입 시 전달. 스캔 결과가 이 cardId와 다르면 등록 차단.
  final String? expectedCardId;
  const ScannerScreen({super.key, this.expectedCardId});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _isProcessing = false;
  bool _resultShowing = false;
  bool _wasModified = false;

  Map<String, dynamic>? _foundCard;
  List<Map<String, dynamic>> _candidates = [];
  String _debugText = '';
  bool _mismatch = false;
  // 스캐너 백엔드 status — 'success' (≥0.75 + gap≥0.04) / 'low_confidence' (0.62~0.75).
  // low_confidence면 자산 등록 막고 후보 선택을 강제해서 오등록 방지.
  String _resultStatus = '';
  // 최근 identify 응답 status. detect의 false positive(쌀자루/문 등)를 가리기 위해 사용.
  // not_found면 OpenCV가 사각형 잡았어도 quad 숨김 — "카드 아닌데 카드라고 인식" 방지.
  String _lastIdentifyStatus = '';
  // 후보 클릭마다 증가. stale enrich 응답을 무시하기 위한 sequence token.
  int _selectSeq = 0;

  // cardId → 보유 자산 요약(개수 + 평가액 합). 결과 시트 "보유 N장 · X원" 표시용.
  final Map<String, _OwnedSummary> _ownedSummaries = {};

  DateTime _lastScan = DateTime(0);
  static const _scanInterval = Duration(milliseconds: 1000);

  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  // 카드 프레임 안에서 위 → 아래로 sweep하는 라인 (스캔이 살아있다는 시각 신호).
  late AnimationController _sweepCtrl;

  void _popWithResult() {
    if (_wasModified) {
      AssetNotifier.instance.notifyChanged();
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      context.pop(_wasModified ? true : null);
    } else {
      // push가 아닌 경로로 들어왔거나 stack이 비어있는 케이스 — 홈으로 fallback
      context.go('/home');
    }
  }

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _glowAnim = Tween(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _initCamera();
    _loadOwnedCards();
  }

  Future<void> _loadOwnedCards() async {
    try {
      final userRes = await ApiClient.get('/api/users/me');
      final userId = (userRes['data'] as Map?)?['userId'] as String? ?? '';
      if (userId.isEmpty) return;
      final res = await ApiClient.get(
        ApiConstants.assets,
        params: {'userId': userId},
      );
      final list = res['data'] as List? ?? [];
      final summaries = <String, _OwnedSummary>{};
      for (final a in list) {
        final cid = (a as Map)['cardId'] as String?;
        if (cid == null) continue;
        // asset_screen.dart 합산과 동일: displayPrice × quantity, quantity 누락 시 1.
        final dp = (a['displayPrice'] as num?)?.toInt() ?? 0;
        final qty = (a['quantity'] as num?)?.toInt() ?? 1;
        final prev = summaries[cid];
        summaries[cid] = _OwnedSummary(
          count: (prev?.count ?? 0) + qty,
          totalValue: (prev?.totalValue ?? 0) + dp * qty,
        );
      }
      if (mounted) {
        setState(() {
          _ownedSummaries
            ..clear()
            ..addAll(summaries);
        });
      }
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted || !mounted) return;

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );

    await _camera!.initialize();
    if (!mounted) return;
    setState(() => _cameraReady = true);
    await _camera!.startImageStream(_onFrame);
  }

  void _onFrame(CameraImage frame) {
    if (_resultShowing) return;
    final now = DateTime.now();
    final shouldScan =
        !_isProcessing && now.difference(_lastScan) >= _scanInterval;
    if (shouldScan) {
      _lastScan = now;
      _processFrame(frame);
    }
  }

  Future<void> _processFrame(CameraImage frame) async {
    if (!mounted || _isProcessing) return;
    _isProcessing = true;

    try {
      final jpegBytes = await _convertToJpeg(frame);
      if (jpegBytes == null) return;

      final res = await ApiClient.postBytes(
        ApiConstants.scannerIdentify,
        fieldName: 'image',
        bytes: jpegBytes,
        filename: 'frame.jpg',
        receiveTimeout: const Duration(seconds: 90),
      );

      final data = res['data'] as Map<String, dynamic>?;
      final status = data?['status'] as String? ?? '';
      final card = data?['card'] as Map<String, dynamic>?;
      final score = data?['score'];

      // identify status 항상 저장. detect false positive 가드용 (build에서 quad 표시 조건).
      // setState로 트리거해야 hideQuad 분기가 즉시 반영됨.
      if (mounted && _lastIdentifyStatus != status) {
        setState(() => _lastIdentifyStatus = status);
      }

      if (status == 'no_card') return;

      if (mounted) setState(() => _debugText = 'status=$status score=$score');

      if (card == null || status == 'not_found') return;

      final rawCandidates = data?['candidates'] as List? ?? [];
      final matchedCardId = card['cardId'] as String?;
      final expected = widget.expectedCardId;
      // expectedCardId가 지정되어 있으면, matchedCardId가 null이거나 다를 때 모두 mismatch로 차단.
      // 비정상 응답으로 null이 와도 등록 UI가 열리지 않도록 가드.
      final mismatched = expected != null && matchedCardId != expected;

      if (mounted) {
        setState(() {
          _foundCard = card;
          _candidates = rawCandidates
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _resultShowing = true;
          _mismatch = mismatched;
          _resultStatus = status;
          _debugText = '';
        });
        await _camera!.stopImageStream();
      }
    } catch (e) {
      if (mounted) setState(() => _debugText = 'error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<List<int>?> _convertToJpeg(CameraImage frame) async {
    try {
      final bytes = frame.planes[0].bytes;
      final rowStride = frame.planes[0].bytesPerRow;
      final w = frame.width;
      final h = frame.height;
      final shouldRotateForPortrait =
          MediaQuery.of(context).orientation == Orientation.portrait && w > h;
      return await Isolate.run(() {
        var image = img.Image.fromBytes(
          width: w,
          height: h,
          bytes: bytes.buffer,
          bytesOffset: bytes.offsetInBytes,
          format: img.Format.uint8,
          numChannels: 4,
          rowStride: rowStride,
          order: img.ChannelOrder.bgra,
        );
        if (shouldRotateForPortrait) {
          image = img.copyRotate(image, angle: -90);
        }
        if (image.width > 1280) {
          image = img.copyResize(image, width: 1280);
        }
        return img.encodeJpg(image, quality: 90);
      });
    } catch (_) {
      return null;
    }
  }

  // 후보 strip 클릭 시 호출. candidates는 가격 enrich 안 돼있어서 그냥 setState하면 가격이
  // 사라짐. 즉시 식별 정보는 갱신하고, 백엔드에서 enriched dto를 받아 가격을 채워준다.
  // 후보를 명시 선택했다는 건 top1 추천을 거부한 것 → 신뢰도 재평가 필요(low_confidence 강제).
  Future<void> _selectCandidate(Map<String, dynamic> c) async {
    final cid = c['cardId'] as String?;
    if (cid == null) return;
    final mySeq = ++_selectSeq;
    setState(() {
      _foundCard = c;
      _resultStatus = 'low_confidence';
    });
    try {
      final res = await ApiClient.get(
        '${ApiConstants.cards}/$cid',
        params: {'withPrice': 'true'},
      );
      final enriched = res['data'] as Map<String, dynamic>?;
      if (!mounted || enriched == null) return;
      // 더 최신 _selectCandidate 호출이 있으면 stale 응답이므로 무시.
      // (cardId 비교만으로는 A→B→A race를 못 잡음 — sequence 토큰이 정답.)
      if (mySeq != _selectSeq) return;
      setState(() => _foundCard = enriched);
    } catch (_) {
      // 가격 fetch 실패해도 식별 정보는 이미 표시 중. 추가 알림 없음.
    }
  }

  Future<void> _dismissResult() async {
    setState(() {
      _foundCard = null;
      _resultShowing = false;
      _mismatch = false;
      _resultStatus = '';
      _lastIdentifyStatus = '';
    });
    _lastScan = DateTime(0);
    if (_camera != null &&
        _camera!.value.isInitialized &&
        !_camera!.value.isStreamingImages) {
      await _camera!.startImageStream(_onFrame);
    }
  }

  // low_confidence(스캐너 신뢰도 0.62~0.75) 시에는 사용자에게 한 번 확인을 받고 등록.
  // 오등록 시 포트폴리오 가치/PnL이 왜곡되므로 안전 마진.
  Future<void> _confirmThenAddToAsset(
    String cardId,
    Map<String, dynamic> card,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFEAB308),
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              '인식 신뢰도 낮음',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        content: const Text(
          '카드 인식 신뢰도가 낮아 다른 카드일 수 있어요.\n'
          '실물 카드와 화면 카드가 일치하는지 다시 확인하세요.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('맞아요, 등록', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _addToAsset(cardId, card);
    }
  }

  Future<void> _addToAsset(String cardId, Map<String, dynamic> card) async {
    final cardName = card['name'] as String? ?? '';
    String? selectedType;
    String selectedLanguage = 'KO';
    String? gradingCompany;
    String? gradeValue;
    bool submitting = false;

    const grades = ['10', '9', '8', '7', '6', '5'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2035),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> submit() async {
            if (selectedType == null || submitting) return;
            // GRADED 선택 시 회사·등급 필수. PSA·BRG만 지원 (CGC/BGS 미지원)
            if (selectedType == 'GRADED' &&
                (gradingCompany == null || gradeValue == null)) {
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(const SnackBar(content: Text('감정사와 등급을 선택해주세요')));
              return;
            }
            // submit 중 사용자가 칩 토글해도 영향 없도록 전체 입력값 snapshot — race 방지
            final submitType = selectedType;
            final submitLanguage = selectedLanguage;
            final submitCompany = gradingCompany;
            final submitGrade = gradeValue;

            setModal(() => submitting = true);
            try {
              final userRes = await ApiClient.get('/api/users/me');
              final userId =
                  (userRes['data'] as Map?)?['userId'] as String? ?? 'guest';
              await ApiClient.post(ApiConstants.assets, {
                'data': {
                  'userId': userId,
                  'cardId': cardId,
                  'cardStatus': submitType,
                  'language': submitLanguage,
                  if (submitType == 'GRADED') 'gradingCompany': submitCompany,
                  if (submitType == 'GRADED') 'gradeValue': submitGrade,
                  'purchasedAt': DateTime.now().toIso8601String().substring(
                    0,
                    10,
                  ),
                },
              });

              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() => _wasModified = true);
              // 새 자산이 추가됐으니 보유 요약 재로드 (개수 + 평가액 정확 반영)
              await _loadOwnedCards();
              if (!mounted) return;
              AssetNotifier.instance.notifyChanged();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('자산에 추가됐습니다'),
                  backgroundColor: Colors.green,
                ),
              );
              _dismissResult();
            } catch (_) {
              if (!ctx.mounted) return;
              setModal(() => submitting = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('등록 실패'),
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
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
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
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '이 카드 등록하기',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cardName,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '카드 언어',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: ['KO', 'JP', 'EN'].map((lang) {
                      final sel = selectedLanguage == lang;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setModal(() => selectedLanguage = lang),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? const Color(0xFF2563EB)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFF2563EB)
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              lang,
                              style: TextStyle(
                                color: sel ? Colors.white : Colors.white70,
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
                  Row(
                    children: [
                      Expanded(
                        child: _RegistrationTypeButton(
                          label: 'RAW 카드',
                          selected: selectedType == 'RAW',
                          onTap: () => setModal(() {
                            selectedType = 'RAW';
                            gradingCompany = null;
                            gradeValue = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _RegistrationTypeButton(
                          label: '등급 카드',
                          selected: selectedType == 'GRADED',
                          onTap: () => setModal(() => selectedType = 'GRADED'),
                        ),
                      ),
                    ],
                  ),
                  // GRADED 선택 시 회사·등급 토큰 노출
                  if (selectedType == 'GRADED') ...[
                    const SizedBox(height: 20),
                    const Text(
                      '감정사',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['PSA', 'BRG'].map((c) {
                        final sel = gradingCompany == c;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setModal(() => gradingCompany = c),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: sel
                                    ? const Color(0xFFFFB300)
                                    : Colors.white10,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel
                                      ? const Color(0xFFFFB300)
                                      : Colors.white24,
                                ),
                              ),
                              child: Text(
                                c,
                                style: TextStyle(
                                  color: sel ? Colors.black87 : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    // PSA10 + EN/JP는 실제 시세 데이터 있을 확률 ↑ → 안내 숨김.
                    // 나머지 조합(BRG, KO+PSA, PSA 9 이하 등)은 RAW 폴백 가능성 안내.
                    if (!((selectedLanguage == 'EN' ||
                            selectedLanguage == 'JP') &&
                        gradingCompany == 'PSA' &&
                        gradeValue == '10')) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Colors.amber,
                              size: 14,
                            ),
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
                    const SizedBox(height: 16),
                    const Text(
                      '등급',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: grades.map((g) {
                        final sel = gradeValue == g;
                        return GestureDetector(
                          onTap: () => setModal(() => gradeValue = g),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? const Color(
                                      0xFFFFB300,
                                    ).withValues(alpha: 0.2)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFFFFB300)
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              g,
                              style: TextStyle(
                                color: sel
                                    ? const Color(0xFFFFB300)
                                    : Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedType == null || submitting
                          ? null
                          : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
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
                              '등록',
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
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _sweepCtrl.dispose();
    _camera?.stopImageStream().then((_) => _camera?.dispose()).catchError((_) {
      _camera?.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !mounted) return;
        _popWithResult();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_cameraReady && _camera != null)
              Positioned.fill(child: _buildCameraPreview()),

            if (!_resultShowing) Positioned.fill(child: _buildCardFrame()),

            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                onPressed: _popWithResult,
              ),
            ),

            if (_debugText.isNotEmpty && !_resultShowing)
              Positioned(
                top: MediaQuery.of(context).padding.top + 56,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _debugText,
                      style: const TextStyle(
                        color: Color(0xFFEAB308),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),

            if (!_resultShowing)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height * 0.77,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _isProcessing
                        ? Row(
                            key: const ValueKey('scanning'),
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF3B82F6),
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                '인식 중...',
                                style: TextStyle(
                                  color: Color(0xFF3B82F6),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            '틀 안에 카드를 맞춰주세요',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                  ),
                ),
              ),

            if (_resultShowing && _foundCard != null && _mismatch)
              Positioned.fill(child: _buildMismatchOverlay()),
            if (_resultShowing && _foundCard != null && !_mismatch)
              Positioned.fill(child: _buildResultOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final size = _camera!.value.previewSize;
    if (size == null) return const ColoredBox(color: Colors.black);
    return OverflowBox(
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(_camera!),
        ),
      ),
    );
  }

  Widget _buildCardFrame() {
    // 인식 중에는 파란색 강조, 대기 중에는 흰색. 화면 가운데 고정 wireframe.
    final color = _isProcessing ? const Color(0xFF3B82F6) : Colors.white;
    return AnimatedBuilder(
      animation: Listenable.merge([_glowAnim, _sweepCtrl]),
      builder: (_, _) => CustomPaint(
        painter: _CardFramePainter(
          glowOpacity: _glowAnim.value,
          frameColor: color,
          sweepProgress: _sweepCtrl.value,
        ),
      ),
    );
  }

  /// expectedCardId 가드 거부 화면. 등록 옵션 없이 재스캔만 허용.
  Widget _buildMismatchOverlay() {
    final card = _foundCard!;
    final name = card['name'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(card);
    final cdnUrl = resolveCdnImageUrl(card);

    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFEF4444),
                size: 56,
              ),
              const SizedBox(height: 16),
              const Text(
                '다른 카드입니다',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '카드 상세에서 진입한 카드와 일치하지 않아\n등록할 수 없습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CardImage(
                        imageUrl: imageUrl,
                        cdnFallbackUrl: cdnUrl,
                        width: 60,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '인식된 카드',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _dismissResult,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '다시 스캔',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _popWithResult,
                child: const Text(
                  '뒤로 가기',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    final card = _foundCard!;
    final cardId = card['cardId'] as String? ?? '';
    final name = card['name'] as String? ?? '';
    final rarity = card['rarityCode'] as String? ?? '';
    final number = card['collectionNumber'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(card);
    final cdnUrl = resolveCdnImageUrl(card);
    final owned = _ownedSummaries[cardId];
    final isOwned = owned != null;
    // ScannerController.getCardWithPrice가 채워주는 KO 환산가 + 전일 변동률.
    final price = (card['koEstimatedPrice'] as num?)?.toInt();
    final pct = (card['gainPct'] as num?)?.toDouble();
    // PriceDisplayPolicy (2026-05-16): 저가 카드 % 숨김/Stage B 전체 숨김/Stage C 변동 적음
    // 스캐너는 한 카드만 보니까 trade_list와 동일 utility 사용 (color 매핑은 일반 패턴)
    int? prevPriceApprox;
    if (price != null && pct != null && pct > -100) {
      prevPriceApprox = (price / (1 + pct / 100)).round();
    }
    final display = PriceDisplayPolicy.buildChangeDisplay(
      lastPrice: price,
      prevPrice: prevPriceApprox,
      prefix: '',
    );
    final String pctLabel = display?.label.trim() ?? '0.0%';
    final Color pctColor = display == null
        ? AppColors.textMuted
        : switch (display.color) {
            // 색상 정책 (feedback_color_policy.md): 양=빨강, 음=파랑.
            PriceChangeColor.positive => AppColors.red,
            PriceChangeColor.negative => AppColors.blue,
            PriceChangeColor.neutral => AppColors.textMuted,
          };
    // 세트명은 너무 길고 잘 안 보이므로 제외. 컬렉션 번호 + 레어도만 표시.
    final metaLine = [
      if (number.isNotEmpty) number,
      if (rarity.isNotEmpty) rarity,
    ].join(' · ');
    // 신뢰도 chip — 백엔드 status가 'success'면 확실, 'low_confidence'면 검토 필요.
    final bool isLowConfidence = _resultStatus == 'low_confidence';
    final String confLabel = isLowConfidence ? '검토 필요' : '확실';
    final Color confFg = isLowConfidence
        ? const Color(0xFFEAB308)
        : AppColors.green;
    final Color confBg = isLowConfidence
        ? const Color(0x29EAB308) // 16% gold
        : const Color(0x2905C072); // 16% green

    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black54,
            child: Center(
              child: _buildDetectedCardFrame(imageUrl, cdnUrl, isOwned),
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111827),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        await _dismissResult();
                        if (!mounted) return;
                        await context.push('/card/$cardId', extra: card);
                        if (mounted) _loadOwnedCards();
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CardImage(
                          imageUrl: imageUrl,
                          cdnFallbackUrl: cdnUrl,
                          width: 90,
                          height: 126,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 신뢰도 chip — 인식 점수 라벨화 (확실 / 검토 필요).
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: confBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isLowConfidence
                                      ? Icons.warning_amber_rounded
                                      : Icons.verified_rounded,
                                  color: confFg,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  confLabel,
                                  style: TextStyle(
                                    color: confFg,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 카드 이름 — 식별 우선.
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          if (metaLine.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              metaLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          // 가격 + 변동률
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: Text(
                                  price != null
                                      ? AppColors.formatPrice(price)
                                      : '시세 없음',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: price != null
                                        ? Colors.white
                                        : AppColors.textMuted,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              if (price != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  pctLabel,
                                  style: TextStyle(
                                    color: pctColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          // 보유 강화 — 동일 카드를 RAW+등급 등 여러 row로 보유하면 합산 평가액 의미 있음.
                          // 장수는 표시 X (같은 cardId 자산 1개 = 1장이 디폴트라 정보 부족).
                          isOwned
                              ? Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: AppColors.green,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '보유 중 · ${AppColors.formatPrice(owned.totalValue)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '미보유',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: isOwned
                                    ? _OwnedBtn()
                                    : _ActionBtn(
                                        label: isLowConfidence
                                            ? '확인 후 등록'
                                            : '자산 등록',
                                        color: const Color(0xFF2563EB),
                                        onTap: () => isLowConfidence
                                            ? _confirmThenAddToAsset(
                                                cardId,
                                                card,
                                              )
                                            : _addToAsset(cardId, card),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _ActionBtn(
                                  label: '상세 보기',
                                  color: const Color(0xFF374151),
                                  onTap: () async {
                                    await _dismissResult();
                                    if (!mounted) return;
                                    await context.push(
                                      '/card/$cardId',
                                      extra: card,
                                    );
                                    if (mounted) _loadOwnedCards();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _dismissResult,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              if (_candidates.length > 1) ...[
                const Divider(color: Colors.white10, height: 1),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    itemCount: _candidates.length,
                    itemBuilder: (_, i) {
                      final c = _candidates[i];
                      final cUrl = resolveCardImageUrl(c);
                      return GestureDetector(
                        onTap: () => _selectCandidate(c),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: i == 0
                                  ? const Color(0xFFEAB308)
                                  : Colors.white24,
                              width: i == 0 ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: CardImage(
                              imageUrl: cUrl,
                              cdnFallbackUrl: resolveCdnImageUrl(c),
                              width: 43,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetectedCardFrame(
    String? imageUrl,
    String? cdnUrl,
    bool isOwned,
  ) {
    // 카메라 화면 인식 카드는 크게 (시선 집중 → 즉시 식별).
    final w = MediaQuery.of(context).size.width * 0.75;
    final h = w * 1.396;
    return Stack(
      alignment: Alignment.center,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CardImage(
                imageUrl: imageUrl,
                cdnFallbackUrl: cdnUrl,
                width: w,
                height: h,
                fit: BoxFit.cover,
              ),
            ),
            if (!isOwned)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        Container(
          width: w + 6,
          height: h + 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEAB308), width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEAB308).withOpacity(0.5),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnedSummary {
  final int count;
  final int totalValue;
  const _OwnedSummary({required this.count, required this.totalValue});
}

// ─── 카드 프레임 가이드 ───────────────────────────────────────────────────────

class _CardFramePainter extends CustomPainter {
  final double glowOpacity;
  final Color frameColor;
  final double sweepProgress; // 0~1 순환. sweep 라인 y 위치 계산.
  const _CardFramePainter({
    required this.glowOpacity,
    required this.frameColor,
    required this.sweepProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintIdleGuide(canvas, size);
  }

  /// 4점 quad에 bilinear 변환된 wireframe 그림.
  /// u,v ∈ [0,1] 카드 normalize 좌표 → quad bilinear.
  /// P(u,v) = (1-u)(1-v)·TL + u(1-v)·TR + uv·BR + (1-u)v·BL
  void _paintCardWireframe(
    Canvas canvas,
    Size size,
    List<Offset> quad, {
    required bool detected,
    required bool drawSweep,
  }) {
    Offset at(double u, double v) {
      final a = (1 - u) * (1 - v),
          b = u * (1 - v),
          c = u * v,
          d = (1 - u) * v;
      return Offset(
        a * quad[0].dx + b * quad[1].dx + c * quad[2].dx + d * quad[3].dx,
        a * quad[0].dy + b * quad[1].dy + c * quad[2].dy + d * quad[3].dy,
      );
    }

    // ── 1. dim overlay (카드 영역 외 어둡게)
    final outerPath = Path()
      ..moveTo(quad[0].dx, quad[0].dy)
      ..lineTo(quad[1].dx, quad[1].dy)
      ..lineTo(quad[2].dx, quad[2].dy)
      ..lineTo(quad[3].dx, quad[3].dy)
      ..close();
    final all = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final dimAlpha = detected ? 0.55 : 0.32;
    canvas.drawPath(
      Path.combine(PathOperation.difference, all, outerPath),
      Paint()..color = Colors.black.withValues(alpha: dimAlpha),
    );

    // ── 2. 외곽 (accent)
    canvas.drawPath(
      outerPath,
      Paint()
        ..color = frameColor.withValues(alpha: detected ? 1.0 : 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ── 3. 내부 wireframe (Codex: detect 시 alpha 낮춰서 시끄럽지 않게)
    final innerAlpha = detected ? 0.28 : 0.45;
    final inner = Paint()
      ..color = Colors.white.withValues(alpha: innerAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 3a. 상단 ribbon (이름/HP 영역)
    final ribbon = Path()
      ..moveTo(at(0.06, 0.04).dx, at(0.06, 0.04).dy)
      ..lineTo(at(0.94, 0.04).dx, at(0.94, 0.04).dy)
      ..lineTo(at(0.94, 0.11).dx, at(0.94, 0.11).dy)
      ..lineTo(at(0.06, 0.11).dx, at(0.06, 0.11).dy)
      ..close();
    canvas.drawPath(ribbon, inner);

    // 3b. art-frame (top-left clipped — 포켓몬 카드 art-frame 모양)
    final art = Path()
      ..moveTo(at(0.17, 0.14).dx, at(0.17, 0.14).dy)
      ..lineTo(at(0.93, 0.14).dx, at(0.93, 0.14).dy)
      ..lineTo(at(0.93, 0.62).dx, at(0.93, 0.62).dy)
      ..lineTo(at(0.07, 0.62).dx, at(0.07, 0.62).dy)
      ..lineTo(at(0.07, 0.24).dx, at(0.07, 0.24).dy)
      ..close();
    canvas.drawPath(art, inner);

    // 3c. info bar (기술명)
    canvas.drawLine(at(0.10, 0.69), at(0.90, 0.69), inner);

    // 3d. 하단 rule box
    final rule = Path()
      ..moveTo(at(0.04, 0.85).dx, at(0.04, 0.85).dy)
      ..lineTo(at(0.96, 0.85).dx, at(0.96, 0.85).dy)
      ..lineTo(at(0.96, 0.93).dx, at(0.96, 0.93).dy)
      ..lineTo(at(0.04, 0.93).dx, at(0.04, 0.93).dy)
      ..close();
    canvas.drawPath(
      rule,
      Paint()
        ..color = Colors.white.withValues(alpha: detected ? 0.22 : 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // ── 4. 4 코너 bracket (quad 4점에서 안쪽으로)
    final edgeAvg = (_dist(quad[0], quad[1]) + _dist(quad[1], quad[2])) / 2;
    final bracketLen = edgeAvg * 0.10;
    final bracketPaint = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = detected ? 5 : 4
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final cur = quad[i];
      final prev = quad[(i + 3) % 4];
      final next = quad[(i + 1) % 4];
      canvas.drawLine(cur, _shorten(cur, prev, bracketLen), bracketPaint);
      canvas.drawLine(cur, _shorten(cur, next, bracketLen), bracketPaint);
    }

    // ── 5. sweep (idle만)
    if (drawSweep) {
      canvas.save();
      canvas.clipPath(outerPath);
      final sweepStart = at(0.05, sweepProgress);
      final sweepEnd = at(0.95, sweepProgress);
      canvas.drawLine(
        sweepStart,
        sweepEnd,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.40)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.restore();
    }
  }

  double _dist(Offset a, Offset b) {
    final dx = a.dx - b.dx, dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// IDLE — 화면 중앙 axis-aligned quad에 동일 wireframe 호출.
  void _paintIdleGuide(Canvas canvas, Size size) {
    final maxW = size.width * 0.88;
    final maxH = size.height * 0.78;
    double cardW = maxW;
    double cardH = cardW * 1.396;
    if (cardH > maxH) {
      cardH = maxH;
      cardW = cardH / 1.396;
    }
    final left = (size.width - cardW) / 2;
    final top = (size.height - cardH) / 2 - 24;
    final quad = [
      Offset(left, top),
      Offset(left + cardW, top),
      Offset(left + cardW, top + cardH),
      Offset(left, top + cardH),
    ];
    _paintCardWireframe(canvas, size, quad, detected: false, drawSweep: true);
  }


  /// from에서 to 방향으로 dist 만큼 진행한 좌표.
  Offset _shorten(Offset from, Offset to, double dist) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-3) return from;
    final t = (dist / len).clamp(0.0, 1.0);
    return Offset(from.dx + dx * t, from.dy + dy * t);
  }

  @override
  bool shouldRepaint(_CardFramePainter old) =>
      old.glowOpacity != glowOpacity ||
      old.frameColor != frameColor ||
      old.sweepProgress != sweepProgress;
}

// ─── 버튼 ────────────────────────────────────────────────────────────────────

class _RegistrationTypeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RegistrationTypeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF2563EB).withOpacity(0.22)
            : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xFF2563EB) : Colors.white12,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white60,
          fontSize: 14,
          fontWeight: selected ? FontWeight.bold : FontWeight.w600,
        ),
      ),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _OwnedBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white24),
    ),
    alignment: Alignment.center,
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, color: Colors.white38, size: 14),
        SizedBox(width: 4),
        Text(
          '보유 중',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
