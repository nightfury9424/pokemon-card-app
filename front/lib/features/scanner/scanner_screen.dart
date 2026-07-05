import 'dart:isolate';
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

  // ── 카메라 생명주기 가드 (프리뷰 native texture 잔상·검정화면 race 방지) ──
  bool _leaving = false; // pop/dispose 진입 — CameraPreview를 build tree에서 즉시 제거
  bool _initializingCamera = false; // _initCamera 재진입 방지
  bool _disposingCamera = false; // dispose 진행 중(재init 금지)
  bool _popping = false; // _popWithResult 중복 진입 방지
  bool _pausedForDetail = false; // 썸네일→/card 상세 위에 있는 동안 스캔/스트림 시작 금지 (더블탭 재진입 겸용)
  int _camGen = 0; // init 세대 토큰 — 늦게 끝난 stale initialize 결과 무시

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

  // 스캔 모드: 'auto' = 실시간 연속 스캔(이미지 스트림), 'capture' = 셔터 1회 촬영.
  // 기본값 auto(구 스캐너 동작). 하단 토글로 전환.
  String _scanMode = 'auto';
  bool _togglingMode = false; // 모드 전환 재진입 가드(연타 시 stream start/stop 꼬임 방지).
  // 모드 전환마다 ++. in-flight identify(자동/촬영)가 전환 후에도 결과를 띄우거나
  // _isProcessing을 되돌려 다음 모드 작업을 방해하지 않도록 소유권을 끊는 토큰.
  int _scanEpoch = 0;

  // ── 자동 스캔(auto) 전용 상태 (구 스트림 경로 복원) ──
  DateTime _lastScan = DateTime(0);
  static const _scanInterval = Duration(milliseconds: 1000);
  // 등록 후 토스트 1.3초 + 마진 = 1.6초 동안 _processFrame skip.
  DateTime? _scanPausedUntil;
  // 최근 등록한 cardId — 같은 카드 즉시 재인식 차단 (60초 cooldown).
  final Map<String, DateTime> _recentlyRegistered = {};
  static const _recentRegisterCooldown = Duration(seconds: 60);

  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  // 카드 프레임 안에서 위 → 아래로 sweep하는 라인 (스캔이 살아있다는 시각 신호).
  late AnimationController _sweepCtrl;

  // 스캐너 이탈 — ★CameraPreview(native Texture)를 트리에서 먼저 제거하고 컨트롤러 dispose를
  // 완료한 뒤에 pop. 즉시 pop하면 pop 트랜지션 동안 마지막 프레임 texture가 홈 위로 남는 잔상 발생.
  Future<void> _popWithResult() async {
    if (_popping) return;
    _popping = true;
    if (_wasModified) {
      AssetNotifier.instance.notifyChanged();
    }
    // 1) preview를 build tree에서 제거(검정 배경) — 다음 build부터 CameraPreview 미렌더.
    _leaving = true;
    if (mounted) setState(() {});
    // 2) 한 프레임 대기 — Texture가 실제로 트리에서 빠지도록.
    await WidgetsBinding.instance.endOfFrame;
    // 3) 컨트롤러 dispose 완료 대기(세션 해제 완료 후 pop).
    await _disposeCamera();
    if (!mounted) return;
    // 4) 그 다음 pop.
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
  // takePicture가 던져 "셔터 먹통"이 되므로, resume 시 컨트롤러를 안전하게 재초기화한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_leaving) return; // 화면 이탈 중이면 아무것도 하지 않음.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _disposeCamera(); // 안전 dispose(세대 토큰 증가로 in-flight init 무효화).
    } else if (state == AppLifecycleState.resumed) {
      _resumeCamera();
    }
  }

  // 이전 dispose가 진행 중이면 완료를 기다린 뒤 재init — iOS AVCaptureSession 해제 완료 전
  // 재초기화 시 검정 프리뷰가 나던 것 방지.
  Future<void> _resumeCamera() async {
    for (var i = 0; i < 40 && _disposingCamera; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || _leaving) return;
    if (_camera == null && !_initializingCamera) _initCamera();
  }

  // 컨트롤러 안전 해제 — 참조 즉시 끊고, 세대 토큰 증가로 진행 중이던 _initCamera 결과를 무효화.
  Future<void> _disposeCamera() async {
    if (_disposingCamera) return;
    final cam = _camera;
    _camera = null;
    _camGen++; // in-flight initialize 결과 폐기.
    if (mounted) setState(() => _cameraReady = false);
    if (cam == null) return;
    _disposingCamera = true;
    try {
      // auto 모드 이미지 스트림이 켜져 있으면 dispose 전에 먼저 정지(스트림 콜백이
      // 해제된 컨트롤러를 건드리는 race 방지).
      if (cam.value.isStreamingImages) {
        try {
          await cam.stopImageStream();
        } catch (_) {}
      }
      await cam.dispose();
    } catch (_) {
    } finally {
      _disposingCamera = false;
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
      Map<String, dynamic>? newestAsset; // 좌하단 썸네일 seed용 = 가장 최근 등록 자산.
      DateTime newestAt = DateTime.fromMillisecondsSinceEpoch(0);
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
        // createdAt 최댓값 = 가장 최근 등록.
        final t = DateTime.tryParse((a['createdAt'] as String?) ?? '');
        if (t != null && t.isAfter(newestAt)) {
          newestAt = t;
          newestAsset = Map<String, dynamic>.from(a);
        }
      }
      // 스캔 첫 진입에도 좌하단 썸네일이 비지 않도록 최근 등록 자산으로 seed.
      // 이번 세션에 등록한 값(_lastRegistered)이 이미 있으면 그게 최신이므로 보존.
      Map<String, dynamic>? seed;
      if (_lastRegistered == null && newestAsset != null) {
        final cardInfo = newestAsset['card'];
        seed = {
          'cardId': newestAsset['cardId'],
          if (newestAsset['assetId'] is String)
            'assetId': newestAsset['assetId'] as String,
          'imageUrl': cardInfo is Map
              ? resolveCardImageUrl(Map<String, dynamic>.from(cardInfo))
              : null,
          if (cardInfo is Map) 'card': Map<String, dynamic>.from(cardInfo),
        };
      }
      if (mounted) {
        setState(() {
          _ownedSummaries
            ..clear()
            ..addAll(summaries);
          if (seed != null) _lastRegistered = seed;
        });
      }
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    // 재진입/이탈/해제중 가드 — 중복 init로 컨트롤러가 2개 생겨 texture가 꼬이는 것 방지.
    if (_initializingCamera || _disposingCamera || _leaving || _camera != null) {
      return;
    }
    _initializingCamera = true;
    final gen = ++_camGen; // 이 init의 세대. 도중 dispose/pop/재init 되면 gen이 어긋남.
    CameraController? controller;
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted || !mounted || gen != _camGen || _leaving) return;

      final cameras = await availableCameras();
      if (cameras.isEmpty || !mounted || gen != _camGen || _leaving) return;

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        // auto 모드 _convertToJpeg가 frame plane을 BGRA로 읽으므로 포맷 고정.
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );
      await controller.initialize();

      // initialize 도중 dispose/pop/재init(세대 변경)·unmount 되었으면 이 컨트롤러는 버린다
      // (_camera에 절대 대입하지 않음 → 고아 texture/검정 방지).
      if (!mounted || gen != _camGen || _leaving) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      controller = null; // 소유권 이전 — finally에서 dispose 안 되게.
      setState(() => _cameraReady = true);
      // auto 모드면 실시간 연속 스캔 스트림 시작(capture 모드는 셔터만 사용).
      // _pausedForDetail: 썸네일→상세 위에 있는 동안 lifecycle 복귀가 스트림을 켜면
      // 상세화면 밑에서 스캔이 돌아 늦은 결과 시트가 뜨므로 금지(복귀 시 재개).
      if (_scanMode == 'auto' &&
          !_leaving &&
          !_pausedForDetail &&
          gen == _camGen &&
          _camera != null &&
          !_camera!.value.isStreamingImages) {
        await _camera!.startImageStream(_onFrame);
        // await 사이 dispose/이탈/세대변경 시 방금 시작한 스트림 정지(고아 구독 방지).
        if (!mounted || _leaving || gen != _camGen) {
          try {
            await _camera?.stopImageStream();
          } catch (_) {}
        }
      }
    } catch (_) {
      // 초기화 실패 — 로컬 컨트롤러 정리, _camera엔 대입하지 않음.
      try {
        await controller?.dispose();
      } catch (_) {}
    } finally {
      _initializingCamera = false;
    }
  }

  // 아이폰 카메라식 셔터 — 탭당 정확히 1회 촬영 → identify.
  // 연속 프레임 스트림 대신 사용자가 명시적으로 촬영할 때만 백엔드 호출.
  Future<void> _onShutter() async {
    if (_scanMode != 'capture') return; // 셔터는 촬영 모드 전용.
    if (_isProcessing || _resultShowing || _leaving) return;
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    // 자동모드 스트림이 아직 정지 안 됐으면 촬영 금지(takePicture-while-streaming 예외 방지).
    if (cam.value.isStreamingImages) return;
    final epoch = _scanEpoch;
    setState(() => _isProcessing = true);
    try {
      final file = await cam.takePicture();
      final raw = await file.readAsBytes();
      // ★orientation bake — takePicture는 회전을 EXIF로만 표기할 수 있고, 스캐너 백엔드
      //   (cv2.imdecode)는 EXIF를 무시한다. 픽셀을 실제 세로 정립본으로 구워서 보내야
      //   DINOv2 매칭 정확도가 유지됨(구 스트림 경로의 copyRotate 보정 대체).
      final bytes = await _bakeUprightJpeg(raw);
      await _identifyJpegBytes(bytes, epoch);
    } catch (e) {
      if (mounted) {
        setState(() => _debugText = 'error: $e');
        AppErrorToast.show(context, '촬영에 실패했어요. 다시 시도해 주세요.');
      }
    } finally {
      // 전환이 없었을 때만 리셋(자동으로 넘어갔으면 자동스캔이 잡은 플래그 보존).
      if (mounted && epoch == _scanEpoch) setState(() => _isProcessing = false);
    }
  }

  // 촬영 JPEG의 EXIF orientation을 픽셀에 실제 적용(bake)해 세로 정립본으로 재인코딩.
  // 디코드/인코드 실패 시 원본 그대로 반환(안전 폴백).
  // ★Isolate에서 실행 — 고해상 촬영사진 decode/bake/encode를 메인스레드서 하면 UI가 몇 초 프리즈
  //   ("인식 중" 멈춤 버그). 스캐너 백엔드가 어차피 1600으로 다운스케일하므로 큰 변 1600으로 줄여 인코딩.
  Future<List<int>> _bakeUprightJpeg(Uint8List raw) async {
    try {
      return await Isolate.run(() {
        final decoded = img.decodeJpg(raw);
        if (decoded == null) return raw;
        var im = img.bakeOrientation(decoded);
        if (im.width > 1600 || im.height > 1600) {
          im = im.width >= im.height
              ? img.copyResize(im, width: 1600)
              : img.copyResize(im, height: 1600);
        }
        return img.encodeJpg(im, quality: 90);
      });
    } catch (_) {
      return raw;
    }
  }

  // ── 자동 스캔(auto) 경로 — 구 스트림 스캐너 복원 ──
  // 카메라 이미지 스트림 콜백. throttle(_scanInterval) + 결과 시트/처리중/이탈 가드.
  void _onFrame(CameraImage frame) {
    if (_leaving || _pausedForDetail || _resultShowing || _scanMode != 'auto') {
      return;
    }
    final now = DateTime.now();
    final shouldScan =
        !_isProcessing && now.difference(_lastScan) >= _scanInterval;
    if (shouldScan) {
      _lastScan = now;
      _processFrame(frame);
    }
  }

  // 프레임 1장을 identify 백엔드로 보내고 결과를 처리. 결과 시트가 열려있거나
  // 등록 직후 cooldown(_scanPausedUntil) 동안은 skip. 매칭되면 스트림을 멈추고 시트 표시.
  Future<void> _processFrame(CameraImage frame) async {
    if (!mounted || _isProcessing || _leaving || _resultShowing) return;
    // 등록 토스트 표시 동안 스캔 일시 중지.
    if (_scanPausedUntil != null &&
        DateTime.now().isBefore(_scanPausedUntil!)) {
      return;
    }
    _isProcessing = true;
    final epoch = _scanEpoch;

    try {
      final jpegBytes = await _convertToJpeg(frame);
      // 전환/이탈 시 즉시 폐기(촬영모드로 넘어갔으면 자동 결과를 띄우지 않음).
      if (jpegBytes == null ||
          !mounted ||
          _leaving ||
          _scanMode != 'auto' ||
          epoch != _scanEpoch) {
        return;
      }

      final res = await ApiClient.postBytes(
        ApiConstants.scannerIdentify,
        fieldName: 'image',
        bytes: jpegBytes,
        filename: 'frame.jpg',
        receiveTimeout: const Duration(seconds: 90),
      );
      if (!mounted || _leaving || _scanMode != 'auto' || epoch != _scanEpoch) {
        return;
      }

      final data = res['data'] as Map<String, dynamic>?;
      final status = data?['status'] as String? ?? '';
      final card = data?['card'] as Map<String, dynamic>?;
      final score = data?['score'];

      // identify status 항상 저장. no_card/not_found 시 하단 안내문 갱신용.
      if (mounted && _lastIdentifyStatus != status) {
        setState(() => _lastIdentifyStatus = status);
      }

      if (status == 'no_card') return;

      // debug text는 dev/profile build에서만. release에서 사용자 노출 X.
      if (kDebugMode && mounted) {
        setState(() => _debugText = 'status=$status score=$score');
      }

      if (card == null || status == 'not_found') return;

      final rawCandidates = data?['candidates'] as List? ?? [];
      final matchedCardId = card['cardId'] as String?;

      // 방금 등록한 카드 즉시 재인식 차단 (60초 cooldown).
      if (matchedCardId != null) {
        final registeredAt = _recentlyRegistered[matchedCardId];
        if (registeredAt != null) {
          if (DateTime.now().difference(registeredAt) <
              _recentRegisterCooldown) {
            return;
          }
          _recentlyRegistered.remove(matchedCardId); // expire
        }
      }

      final expected = widget.expectedCardId;
      // expectedCardId 지정 시 matchedCardId가 null이거나 다르면 mismatch로 차단.
      final mismatched = expected != null && matchedCardId != expected;

      if (mounted && !_leaving) {
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
        // 결과 시트 표시 → 스트림 정지(dismiss 시 재시작).
        final cam = _camera;
        if (cam != null && cam.value.isStreamingImages) {
          try {
            await cam.stopImageStream();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) setState(() => _debugText = 'error: $e');
    } finally {
      // 전환이 없었을 때(이 작업이 여전히 현재 소유자)만 리셋 — 전환 후 새 모드가
      // 이미 잡은 _isProcessing을 stale identify가 되돌리지 못하게.
      if (epoch == _scanEpoch) _isProcessing = false;
    }
  }

  // BGRA8888 카메라 프레임 → 세로 정립 JPEG. plane 바이트를 isolate에서 인코딩.
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

  // auto ↔ capture 전환. auto로 가면 스트림 시작, capture로 가면 스트림 정지.
  Future<void> _setScanMode(String mode) async {
    if (_togglingMode || mode == _scanMode) return; // 재진입/동일모드 차단.
    _togglingMode = true;
    try {
      // 전환 즉시 이전 모드의 in-flight 작업 소유권을 끊고(_scanEpoch++) 처리중 플래그를
      // 리셋 → 셔터/자동스캔이 곧바로 다시 동작 가능(이전 identify가 끝나며 물고 있던
      // "인식 중"이 새 모드에서 남지 않음).
      _scanEpoch++;
      if (mounted) {
        setState(() {
          _scanMode = mode;
          _isProcessing = false;
        });
      }
      final cam = _camera;
      if (cam == null || !cam.value.isInitialized || _leaving) return;
      if (mode == 'capture') {
        if (cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
      } else {
        // auto — 결과 시트가 열려있지 않을 때만 즉시 재개(시트 dismiss 시 재개됨).
        if (_cameraReady &&
            !_resultShowing &&
            !_pausedForDetail &&
            !cam.value.isStreamingImages) {
          _lastScan = DateTime(0);
          await cam.startImageStream(_onFrame);
        }
      }
    } catch (_) {
    } finally {
      _togglingMode = false;
    }
  }

  // 촬영한 JPEG 바이트를 기존 identify 백엔드에 1회 전송하고 결과를 처리.
  // (구 _processFrame의 요청/결과 처리 로직을 셔터 흐름에서 재사용하도록 추출.)
  Future<void> _identifyJpegBytes(List<int> bytes, int epoch) async {
    if (!mounted) return;
    try {
      final res = await ApiClient.postBytes(
        ApiConstants.scannerIdentify,
        fieldName: 'image',
        bytes: bytes,
        filename: 'capture.jpg',
        receiveTimeout: const Duration(seconds: 90),
      );
      // 촬영 후 모드 전환/이탈 시 stale 결과 폐기.
      if (!mounted || _leaving || _scanMode != 'capture' || epoch != _scanEpoch) {
        return;
      }

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
    _lastScan = DateTime(0);
    // auto 모드면 결과 시트를 닫으며 실시간 스캔 스트림을 재개(capture는 셔터 대기).
    final cam = _camera;
    if (_scanMode == 'auto' &&
        !_leaving &&
        cam != null &&
        cam.value.isInitialized &&
        !cam.value.isStreamingImages) {
      try {
        await cam.startImageStream(_onFrame);
      } catch (_) {}
    }
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
      iconColor: AppColors.gold,
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
      backgroundColor: AppColors.surfaceCard,
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
              // auto 모드: 등록 직후 즉시 재인식/재-pop 방지 — 토스트 동안 스캔 일시정지
              // (1.6초) + 방금 등록한 cardId 60초 cooldown.
              _scanPausedUntil =
                  DateTime.now().add(const Duration(milliseconds: 1600));
              _recentlyRegistered[cardId] = DateTime.now();
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
                        backgroundColor: AppColors.blue,
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
    _leaving = true; // 혹시 남은 build/콜백이 CameraPreview·init을 못 타게.
    _camGen++; // in-flight initialize 결과 폐기.
    WidgetsBinding.instance.removeObserver(this);
    _glowCtrl.dispose();
    _sweepCtrl.dispose();
    // 정상 이탈은 _popWithResult→_disposeCamera가 스트림을 먼저 stop. 여기선 controller.dispose가
    // auto 모드 스트림까지 정리(dispose는 sync라 await 불가). 참조 끊고 해제(setState 금지).
    final cam = _camera;
    _camera = null;
    cam?.dispose();
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
            if (_cameraReady && _camera != null && !_leaving)
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

            // 현재 스캔 모드 상태 표시(상단 중앙, 글자).
            if (!_resultShowing && _cameraReady && !_leaving)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 0,
                right: 0,
                child: Center(child: _buildModeStatus()),
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
                        color: AppColors.gold,
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

            // 아이폰 카메라식 검정 하단바 — 좌:썸네일 · 중앙:셔터(촬영모드) · 우:원형 모드 전환.
            if (!_resultShowing && _cameraReady && !_leaving)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black,
                  padding: EdgeInsets.only(
                    top: 22,
                    bottom: MediaQuery.of(context).padding.bottom + 18,
                  ),
                  child: SizedBox(
                    height: 84,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 중앙 셔터 — 촬영 모드만. 자동 모드는 연속 스캔(중앙 비움).
                        if (_scanMode == 'capture')
                          _ShutterButton(
                              busy: _isProcessing, onTap: _onShutter),
                        // 좌: 최근 등록 카드 썸네일.
                        if (_lastRegistered != null)
                          Positioned(
                            left: 28,
                            child: _buildLastRegisteredThumb(),
                          ),
                        // 우: 모드 전환(원형, 아이폰 플립 위치) — 자동↔촬영.
                        Positioned(
                          right: 28,
                          child: _buildModeSwitchCircle(),
                        ),
                      ],
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

  // 상단 현재 모드 표시(글자) — 자동/촬영 상태 인디케이터.
  Widget _buildModeStatus() {
    final isAuto = _scanMode == 'auto';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isAuto ? Icons.autorenew_rounded : Icons.photo_camera_rounded,
              color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            isAuto ? '자동 스캔' : '촬영 스캔',
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // 하단 모드 선택 스트립(아이폰 카메라 하단바식) — [자동][촬영]. 현재 하이라이트, 탭 전환.
  // 우하단 원형 모드 전환 버튼(아이폰 카메라 플립 위치) — 자동↔촬영. 현재 모드는 상단 글자 표시.
  Widget _buildModeSwitchCircle() {
    return GestureDetector(
      onTap: () => _setScanMode(_scanMode == 'auto' ? 'capture' : 'auto'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF2C2C2E),
        ),
        child: const Icon(Icons.sync_rounded, color: Colors.white, size: 28),
      ),
    );
  }

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
  Future<void> _openLastRegistered() async {
    if (_pausedForDetail || _leaving) return; // 더블탭 재진입·이탈 중 push 금지
    final reg = _lastRegistered;
    if (reg == null) return;
    final cardId = reg['cardId'] as String?;
    if (cardId == null || cardId.isEmpty) return;
    final assetId = reg['assetId'] as String?;
    final card = reg['card'];
    final myAsset = <String, dynamic>{'cardId': cardId};
    if (assetId != null) myAsset['assetId'] = assetId;
    if (card is Map) myAsset['card'] = Map<String, dynamic>.from(card);

    // ★구 `if (_isProcessing) return;` 가드 대체. 자동 모드는 1초 간격으로 계속 스캔 →
    // identify 도는 동안 _isProcessing=true라, 그 창에 걸린 썸네일 탭이 통째로 씹혔다
    // (모드 전환 후에야 먹히던 증상의 원인). 탭은 항상 먹히게 하되, 이동 직전에
    // in-flight identify를 무효화(_scanEpoch++)하고 _pausedForDetail로 새 스캔/스트림
    // 시작을 봉인(stop await 틈의 큐 프레임·lifecycle 복귀 재시작 포함) → 늦은 자동 인식
    // 결과가 /card 상세 위로 시트를 띄우는 혼란을 방지. 복귀 시 자동 모드면 재개.
    _pausedForDetail = true;
    _scanEpoch++;
    _isProcessing = false;
    final cam = _camera;
    if (cam != null && cam.value.isStreamingImages) {
      try {
        await cam.stopImageStream();
      } catch (_) {}
    }

    if (!mounted || _leaving) {
      _pausedForDetail = false;
      return;
    }
    try {
      await context.push('/card/$cardId', extra: {'myAsset': myAsset});
    } finally {
      _pausedForDetail = false;
    }
    if (!mounted) return;
    _loadOwnedCards();
    _lastScan = DateTime(0);
    final resumeCam = _camera;
    if (_scanMode == 'auto' &&
        !_leaving &&
        !_resultShowing &&
        resumeCam != null &&
        resumeCam.value.isInitialized &&
        !resumeCam.value.isStreamingImages) {
      try {
        await resumeCam.startImageStream(_onFrame);
      } catch (_) {}
    }
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
                color: AppColors.red,
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
                    backgroundColor: AppColors.blue,
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
                    color: AppColors.blue,
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
            border: Border.all(color: AppColors.gold, width: 3),
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
                    color: AppColors.blue,
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
