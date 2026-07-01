import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/constants/api_constants.dart';
import '../../core/notifiers/asset_notifier.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/price_display_policy.dart';
import '../../core/utils/price_label.dart';
import '../../core/widgets/card_image.dart';
import '../../core/widgets/app_segmented_toggle.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/app_error_toast.dart';

class ScannerScreen extends StatefulWidget {
  /// 카드 상세에서 진입 시 전달. 스캔 결과가 이 cardId와 다르면 등록 차단.
  final String? expectedCardId;
  const ScannerScreen({super.key, this.expectedCardId});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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

  // 이번 세션에서 가장 최근 등록한 카드 — 좌하단 앨범 썸네일(아이폰 카메라 스타일)용.
  // {cardId, assetId?, imageUrl?, card}. null이면 썸네일 숨김.
  Map<String, dynamic>? _lastRegistered;

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
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _loadOwnedCards();
  }

  // 앱 백그라운드/복귀 — iOS는 백그라운드 시 카메라 세션을 해제. 프리뷰가 얼어붙고
  // takePicture가 던져 "셔터 먹통"이 되므로, resume 시 컨트롤러를 재초기화한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final cam = _camera;
      _camera = null;
      if (mounted) setState(() => _cameraReady = false);
      cam?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_camera == null) _initCamera();
    }
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
    );

    await _camera!.initialize();
    if (!mounted) return;
    setState(() => _cameraReady = true);
  }

  // 아이폰 카메라식 셔터 — 탭당 정확히 1회 촬영 → identify.
  // 연속 프레임 스트림 대신 사용자가 명시적으로 촬영할 때만 백엔드 호출.
  Future<void> _onShutter() async {
    if (_isProcessing || _resultShowing) return;
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    setState(() => _isProcessing = true);
    try {
      final file = await cam.takePicture();
      final raw = await file.readAsBytes();
      // ★orientation bake — takePicture는 회전을 EXIF로만 표기할 수 있고, 스캐너 백엔드
      //   (cv2.imdecode)는 EXIF를 무시한다. 픽셀을 실제 세로 정립본으로 구워서 보내야
      //   DINOv2 매칭 정확도가 유지됨(구 스트림 경로의 copyRotate 보정 대체).
      final bytes = await _bakeUprightJpeg(raw);
      await _identifyJpegBytes(bytes);
    } catch (e) {
      if (mounted) {
        setState(() => _debugText = 'error: $e');
        AppErrorToast.show(context, '촬영에 실패했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 촬영 JPEG의 EXIF orientation을 픽셀에 실제 적용(bake)해 세로 정립본으로 재인코딩.
  // 디코드/인코드 실패 시 원본 그대로 반환(안전 폴백).
  Future<Uint8List> _bakeUprightJpeg(Uint8List raw) async {
    try {
      final decoded = img.decodeJpg(raw);
      if (decoded == null) return raw;
      final baked = img.bakeOrientation(decoded);
      return img.encodeJpg(baked, quality: 90);
    } catch (_) {
      return raw;
    }
  }

  // 촬영한 JPEG 바이트를 기존 identify 백엔드에 1회 전송하고 결과를 처리.
  // (구 _processFrame의 요청/결과 처리 로직을 셔터 흐름에서 재사용하도록 추출.)
  Future<void> _identifyJpegBytes(List<int> bytes) async {
    if (!mounted) return;
    try {
      final res = await ApiClient.postBytes(
        ApiConstants.scannerIdentify,
        fieldName: 'image',
        bytes: bytes,
        filename: 'capture.jpg',
        receiveTimeout: const Duration(seconds: 90),
      );

      final data = res['data'] as Map<String, dynamic>?;
      final status = data?['status'] as String? ?? '';
      final card = data?['card'] as Map<String, dynamic>?;
      final score = data?['score'];

      // identify status 항상 저장. no_card/not_found 시 하단 안내문 갱신용.
      if (mounted && _lastIdentifyStatus != status) {
        setState(() => _lastIdentifyStatus = status);
      }

      if (status == 'no_card') return;

      // Phase 1 (2026-05-20): debug text는 dev/profile build에서만. release에서 사용자 노출 X.
      if (kDebugMode && mounted) {
        setState(() => _debugText = 'status=$status score=$score');
      }

      // no-match/실패 — 결과 시트를 띄우지 않고 안내문만 갱신. 사용자는 셔터로 재촬영.
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
      }
    } catch (e) {
      // 식별 요청 실패/타임아웃(90s) — release에선 debug text가 안 보이므로 사용자 토스트로 안내.
      if (mounted) {
        setState(() => _debugText = 'error: $e');
        AppErrorToast.show(context, '카드 인식에 실패했어요. 다시 촬영해 주세요.');
      }
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

  // 결과 시트를 닫고 프리뷰로 복귀. 스트림이 없으므로 상태 리셋만 하면
  // 다시 셔터를 눌러 재촬영할 수 있다. (기존 await 호출부 유지 위해 Future 시그니처 보존.)
  Future<void> _dismissResult() async {
    setState(() {
      _foundCard = null;
      _resultShowing = false;
      _mismatch = false;
      _resultStatus = '';
      _lastIdentifyStatus = '';
    });
  }

  // low_confidence(스캐너 신뢰도 0.62~0.75) 시에는 사용자에게 한 번 확인을 받고 등록.
  // 오등록 시 포트폴리오 가치/PnL이 왜곡되므로 안전 마진.
  Future<void> _confirmThenAddToAsset(
    String cardId,
    Map<String, dynamic> card,
  ) async {
    final ok = await AppConfirmDialog.show(
      context,
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFEAB308),
      title: '인식 신뢰도 낮음',
      message:
          '카드 인식 신뢰도가 낮아 다른 카드일 수 있어요.\n'
          '실물 카드와 화면 카드가 일치하는지 다시 확인하세요.',
      cancelLabel: '취소',
      confirmLabel: '맞아요, 등록',
    );
    if (ok == true && mounted) {
      await _addToAsset(cardId, card);
    }
  }

  Future<void> _addToAsset(String cardId, Map<String, dynamic> card) async {
    final cardName = card['name'] as String? ?? '';
    // ★카드가 실제 가진 발매판만 노출 — EN 전용 promo(고흐 피카츄 등)를 KO로
    //   오등록하던 문제 방지. language(주발매판) + jp/enScrydexRef(타판 존재)로 판단.
    final cardLang = (card['language'] as String?)?.trim().toUpperCase();
    final hasJpRef = (card['jpScrydexRef'] as String?)?.trim().isNotEmpty ?? false;
    final hasEnRef = (card['enScrydexRef'] as String?)?.trim().isNotEmpty ?? false;
    final langsForCard = <String>[
      if (cardLang == 'KO') 'KO',
      if (cardLang == 'JP' || hasJpRef) 'JP',
      if (cardLang == 'EN' || hasEnRef) 'EN',
    ];
    // 언어 정보 없으면(방어) 기존처럼 3개 다 — 등록 자체를 막지 않게.
    final availableLanguages =
        langsForCard.isNotEmpty ? langsForCard : const ['KO', 'JP', 'EN'];
    String? selectedType;
    String selectedLanguage =
        (cardLang != null && availableLanguages.contains(cardLang))
            ? cardLang
            : availableLanguages.first;
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
              AppInfoToast.show(ctx, '감정사와 등급을 선택해주세요');
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
              final res = await ApiClient.post(ApiConstants.assets, {
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
              // 거부(HTTP 200 바디 status=fail)를 성공 오인하지 않게.
              if (res['status'] != 'success') {
                AppErrorToast.show(
                    context,
                    (res['message'] is String &&
                            (res['message'] as String).trim().isNotEmpty)
                        ? res['message'] as String
                        : '내 카드 추가에 실패했어요.');
                return;
              }
              Navigator.pop(ctx);
              // 방금 생성된 자산 — 좌하단 앨범 썸네일 + 탭 시 자산 상세 진입용으로 보관.
              final createdAsset = res['data'] as Map<String, dynamic>?;
              setState(() {
                _wasModified = true;
                _lastRegistered = {
                  'cardId': cardId,
                  if (createdAsset?['assetId'] is String)
                    'assetId': createdAsset!['assetId'] as String,
                  'imageUrl': resolveCardImageUrl(card),
                  'card': card,
                };
              });
              // 새 자산이 추가됐으니 보유 요약 재로드 (개수 + 평가액 정확 반영)
              await _loadOwnedCards();
              if (!mounted) return;
              AssetNotifier.instance.notifyChanged();
              AppSuccessToast.show(context, '내 카드에 추가됐습니다');
              _dismissResult();

              // Phase 6: 카드 상세에서 expectedCardId로 진입한 경우 등록 직후 자동 복귀.
              // 일반 흐름(expectedCardId == null)에는 영향 없음. return으로 후속 setState/snackbar 차단.
              if (widget.expectedCardId != null && mounted) {
                context.pop(true);
                return;
              }
            } catch (_) {
              if (!ctx.mounted) return;
              setModal(() => submitting = false);
              if (mounted) {
                AppErrorToast.show(context, '등록 실패');
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
                  // 토글 통일 (Hotfix 10-5): 공통 AppSegmentedToggle 로 일관.
                  AppSegmentedToggle(
                    labels: availableLanguages,
                    selectedIndex: availableLanguages.indexOf(selectedLanguage),
                    onChanged: (i) => setModal(
                      () => selectedLanguage = availableLanguages[i],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppSegmentedToggle(
                    labels: const ['RAW 카드', '등급 카드'],
                    selectedIndex: selectedType == null
                        ? -1
                        : (selectedType == 'RAW' ? 0 : 1),
                    onChanged: (i) => setModal(() {
                      if (i == 0) {
                        selectedType = 'RAW';
                        gradingCompany = null;
                        gradeValue = null;
                      } else {
                        selectedType = 'GRADED';
                      }
                    }),
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
                    AppSegmentedToggle(
                      labels: const ['PSA', 'BRG'],
                      selectedIndex: gradingCompany == null
                          ? -1
                          : (gradingCompany == 'PSA' ? 0 : 1),
                      onChanged: (i) => setModal(
                        () => gradingCompany = i == 0 ? 'PSA' : 'BRG',
                      ),
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
                    AppSegmentedToggle(
                      labels: grades,
                      selectedIndex:
                          gradeValue == null ? -1 : grades.indexOf(gradeValue!),
                      onChanged: (i) =>
                          setModal(() => gradeValue = grades[i]),
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
    WidgetsBinding.instance.removeObserver(this);
    _glowCtrl.dispose();
    _sweepCtrl.dispose();
    // 프리뷰 전용 — 이미지 스트림을 시작하지 않으므로 stopImageStream 불필요. 컨트롤러만 해제.
    _camera?.dispose();
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

            if (kDebugMode && _debugText.isNotEmpty && !_resultShowing)
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
                                  color: Color(0xFF60A5FA),
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                '인식 중...',
                                style: TextStyle(
                                  color: Color(0xFF60A5FA),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        : (_lastIdentifyStatus == 'not_found'
                              ? const Column(
                                  key: ValueKey('not_found'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '카드를 다시 프레임 안에 맞춰주세요',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      '정면으로 카드 외곽이 프레임 안에 들어가게 해주세요',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
                                )
                              : const Column(
                                  key: ValueKey('idle'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '카드를 프레임 안에 맞춰주세요',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      '밝은 곳에서 정면으로 촬영하면 더 정확해요',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
                                )),
                  ),
                ),
              ),

            // 아이폰 카메라식 하단 컨트롤 — 셔터(중앙) + 최근 등록 앨범 썸네일(좌하단).
            if (!_resultShowing && _cameraReady)
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom + 28,
                child: SizedBox(
                  height: 76,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _ShutterButton(busy: _isProcessing, onTap: _onShutter),
                      if (_lastRegistered != null)
                        Positioned(
                          left: 28,
                          child: _buildLastRegisteredThumb(),
                        ),
                    ],
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

  // 좌하단 앨범 썸네일 — 이번 세션 최근 등록 카드. 탭 시 그 카드의 자산 상세로 이동.
  Widget _buildLastRegisteredThumb() {
    final reg = _lastRegistered!;
    final imageUrl = reg['imageUrl'] as String?;
    return GestureDetector(
      onTap: _openLastRegistered,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CardImage(
            imageUrl: imageUrl,
            width: 54,
            height: 54,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  // 최근 등록 카드의 자산 상세로 이동 — 보유 카드 열기와 동일 목적지(/card/:cardId + myAsset).
  // assetId가 있으면 card_detail이 /api/assets/{id}로 풀 자산을 refetch, 없으면 cardId로 보유 조회.
  void _openLastRegistered() {
    if (_isProcessing) return; // 촬영/식별 진행 중엔 이동 막음(진행 중 결과가 뒤 라우트에서 뜨는 혼란 방지).
    final reg = _lastRegistered;
    if (reg == null) return;
    final cardId = reg['cardId'] as String?;
    if (cardId == null || cardId.isEmpty) return;
    final assetId = reg['assetId'] as String?;
    final card = reg['card'];
    final myAsset = <String, dynamic>{'cardId': cardId};
    if (assetId != null) myAsset['assetId'] = assetId;
    if (card is Map) myAsset['card'] = Map<String, dynamic>.from(card);
    context.push('/card/$cardId', extra: {'myAsset': myAsset}).then((_) {
      if (mounted) _loadOwnedCards();
    });
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
    // C-1 Lite (2026-05-20): 인식 중 soft blue (60A5FA), idle white.
    // hard blue (3B82F6)는 너무 강조 → soft tint로 고급스러움 유지.
    final color = _isProcessing ? const Color(0xFF60A5FA) : Colors.white;
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
    // ★KO 가격은 대부분 예상가치 — '시세' 오해 방지 라벨(price_confidence 정책, card_detail과 동일 유틸).
    final String priceLabel = PriceLabel.resolve(labelType: card['koPriceLabelType'] as String?, price: price);
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
    final Color confFg = isLowConfidence ? AppColors.gold : AppColors.green;
    final Color confBg = isLowConfidence
        ? AppColors.gold.withValues(alpha: 0.16)
        : AppColors.green.withValues(alpha: 0.16);

    return Column(
      children: [
        Expanded(
          child: Container(
            // C-2 (2026-05-20): dim 진하게 → 카드 영역 강조 (이전 0.54 → 0.70).
            color: Colors.black.withValues(alpha: 0.70),
            child: Center(
              child: _buildDetectedCardFrame(imageUrl, isOwned),
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            // C-2: hardcoded #111827 → AppColors.surfaceElevated 토큰 (앱 일관).
            color: AppColors.surfaceElevated,
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
                          // ★가격이 예상가치임을 명시(290원만 보이면 시세로 오해). KO=대부분 한국판 예상가.
                          if (price != null) ...[
                            Text(
                              priceLabel,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                          ],
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
                                            : '카드 등록',
                                        // C-2: 앱 표준 AppColors.blue (#1B64DA) 통일.
                                        color: AppColors.blue,
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
                                  // C-2: 더 어두운 surface로 secondary CTA 톤다운.
                                  color: AppColors.surfaceCard,
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
                // C-3 (2026-05-20): top-3 후보 UX — thumbnail ↑ + 카드명 + "추천" badge.
                SizedBox(
                  height: 116,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _candidates.length,
                    itemBuilder: (_, i) {
                      final c = _candidates[i];
                      final cUrl = resolveCardImageUrl(c);
                      final cName = c['name'] as String? ?? '';
                      final isTop = i == 0;
                      return GestureDetector(
                        onTap: () => _selectCandidate(c),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          margin: const EdgeInsets.only(right: 10),
                          width: 64,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(
                                        color: isTop
                                            ? AppColors.gold
                                            : Colors.white24,
                                        width: isTop ? 2 : 1,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: CardImage(
                                        imageUrl: cUrl,
                                        width: 56,
                                        height: 78,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  if (isTop)
                                    Positioned(
                                      top: -6,
                                      right: -6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.gold,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          '추천',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                cName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isTop
                                      ? Colors.white
                                      : Colors.white60,
                                  fontSize: 10,
                                  fontWeight: isTop
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
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
                color: const Color(0xFFEAB308).withValues(alpha: 0.5),
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

    // ── 1. dim overlay (카드 영역 외 어둡게) — Phase 1 (2026-05-20): idle alpha 강화
    final outerPath = Path()
      ..moveTo(quad[0].dx, quad[0].dy)
      ..lineTo(quad[1].dx, quad[1].dy)
      ..lineTo(quad[2].dx, quad[2].dy)
      ..lineTo(quad[3].dx, quad[3].dy)
      ..close();
    final all = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final dimAlpha = detected ? 0.65 : 0.55;
    canvas.drawPath(
      Path.combine(PathOperation.difference, all, outerPath),
      Paint()..color = Colors.black.withValues(alpha: dimAlpha),
    );

    // ── 2. 외곽 (accent) — Phase 1: 얇게, 시각 노이즈 줄임
    canvas.drawPath(
      outerPath,
      Paint()
        ..color = frameColor.withValues(alpha: detected ? 1.0 : 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = detected ? 2.5 : 1.5,
    );

    // ── 3. 내부 wireframe 제거 (Phase 1, 2026-05-20)
    //   ribbon/art-frame/info-bar/rule box → 카드 외곽만 맞추는 단순 UX.
    //   사용자가 "내 카드 안에 그림 맞춰야 하나?" 혼란 제거.
    //   TCGplayer/StripeCardScan/VisionKit 표준 패턴.

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

// 아이폰 카메라식 셔터 — 흰 원(외곽 링 + 내부 원). busy면 비활성 + 스피너.
class _ShutterButton extends StatelessWidget {
  final bool busy;
  final Future<void> Function() onTap;
  const _ShutterButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : () => onTap(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: busy ? Colors.white54 : Colors.white,
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF2563EB),
                  ),
                )
              : null,
        ),
      ),
    );
  }
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
    behavior: HitTestBehavior.opaque,
    child: Container(
      // C-2: vertical padding 10 → 14 (height ~48, 토스 표준 CTA 사이즈).
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
    ),
  );
}

class _OwnedBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    // C-2: _ActionBtn과 height 통일.
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(12),
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
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    ),
  );
}
