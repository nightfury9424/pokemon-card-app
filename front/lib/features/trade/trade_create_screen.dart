import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/feature_flags.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/thousands_comma_formatter.dart';
import '../../core/widgets/card_image.dart';
import '../../core/widgets/trade_safety_notice.dart';

class _TradePhoto {
  final File file;
  final bool isAutoFilled;
  final String? imageType;

  const _TradePhoto({
    required this.file,
    required this.isAutoFilled,
    this.imageType,
  });
}

class TradeCreateScreen extends StatefulWidget {
  final String cardId;
  final String? cardName;
  final String? rarity;
  final String? imageUrl;
  final String? assetId;
  final String? cardStatus;
  final double? estimatedGrade;
  final String? gradingCompany;
  final String? gradeValue;
  final String? certNumber;
  final int? defaultPrice;
  /// DraggableScrollableSheet로 띄울 때 sheet 스크롤 컨트롤러 (부분→스크롤 시 full 확장).
  /// null = 기존 풀스크린 라우트 모드.
  final ScrollController? sheetScrollController;

  const TradeCreateScreen({
    super.key,
    required this.cardId,
    this.cardName,
    this.rarity,
    this.imageUrl,
    this.assetId,
    this.cardStatus,
    this.estimatedGrade,
    this.gradingCompany,
    this.gradeValue,
    this.certNumber,
    this.defaultPrice,
    this.sheetScrollController,
  });

  @override
  State<TradeCreateScreen> createState() => _TradeCreateScreenState();
}

class _TradeCreateScreenState extends State<TradeCreateScreen> {
  static const int _maxPhotos = 5;

  final _memoCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  // inline error 보일 때 자동 scroll-to-top — body 하단에서 등록 실패해도 사용자가 에러 즉시 보게 (Codex 즉시수정).
  final _scrollCtrl = ScrollController();
  final List<_TradePhoto> _photos = [];
  int? _selectedPhotoIndex;
  bool _submitting = false;
  // 등록 실패 또는 사진 누락 inline error (SnackBar 금지 정책, feedback_hoga_design_invariants.md 가드레일 11).
  String? _submitError;
  // Phase 5: 자산 이미지 자동첨부 진행/실패 상태 — 사진 영역 spinner/안내.
  bool _loadingAssetImages = false;
  String? _assetImageError;

  String get _cardStatus => widget.cardStatus ?? 'RAW';

  String? get _condition {
    final g = widget.estimatedGrade;
    if (g == null) return null;
    if (g >= 9.0) return '최상';
    if (g >= 7.0) return '상';
    if (g >= 5.0) return '중';
    if (g >= 3.0) return '중하';
    return '하';
  }

  @override
  void initState() {
    super.initState();
    if (widget.defaultPrice != null && widget.defaultPrice! > 0) {
      // 호출자(_onSellTap)에서 이미 tick floor 처리. 100원 재-round 제거 (Codex 즉시수정).
      // 천 단위 콤마 포맷 적용 — card_detail의 매수 등록/수정 sheet와 동일 UX.
      _priceCtrl.text = formatThousands(widget.defaultPrice!);
    }
    if (widget.assetId != null) _loadAssetImages(widget.assetId!);
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    _priceCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssetImages(String assetId) async {
    if (mounted) {
      setState(() {
        _loadingAssetImages = true;
        _assetImageError = null;
      });
    }
    try {
      debugPrint('[TradeCreate] _loadAssetImages start assetId=$assetId');
      final res = await ApiClient.get('/api/assets/$assetId/images');
      final data = res['data'];
      if (data is! List) {
        debugPrint('[TradeCreate] _loadAssetImages — data not List: $data');
        return;
      }
      final images = List<Map<String, dynamic>>.from(data);
      debugPrint('[TradeCreate] _loadAssetImages — ${images.length} images: '
          '${images.map((i) => i['imageType']).toList()}');
      final autoPhotos = <_TradePhoto>[];

      for (final imageType in ['FRONT', 'BACK']) {
        final image = images
            .where((i) => i['imageType'] == imageType)
            .firstOrNull;
        final relUrl = image?['imageUrl'] as String?;
        if (relUrl == null) {
          debugPrint('[TradeCreate] _loadAssetImages — $imageType skip (relUrl null)');
          continue;
        }

        final fullUrl = relUrl.startsWith('http')
            ? relUrl
            : '${ApiConstants.baseUrl}$relUrl';

        // prod 인증 toggle(API_AUTH_ENFORCED=true) 시 /api/images/secure/** 는 JWT 필요.
        // 새 Dio() 사용하면 interceptor 미적용 → 401/403. ApiClient.downloadBytes 사용.
        final bytes = await ApiClient.downloadBytes(fullUrl);
        if (bytes != null) {
          final type = imageType.toLowerCase();
          final docsDir = await getApplicationDocumentsDirectory();
          final tempFile = File('${docsDir.path}/asset_${type}_$assetId.jpg');
          await tempFile.writeAsBytes(bytes);
          autoPhotos.add(
            _TradePhoto(
              file: tempFile,
              isAutoFilled: true,
              imageType: imageType,
            ),
          );
        } else {
          debugPrint('[TradeCreate] _loadAssetImages — $imageType download fail (no bytes)');
        }
      }

      if (autoPhotos.isNotEmpty && mounted) {
        debugPrint('[TradeCreate] _loadAssetImages — attached ${autoPhotos.length} photos');
        setState(() {
          final slots = (_maxPhotos - _photos.length).clamp(0, _maxPhotos);
          _photos.insertAll(0, autoPhotos.take(slots));
        });
      } else {
        debugPrint('[TradeCreate] _loadAssetImages — no autoPhotos (mounted=$mounted)');
      }
    } catch (e, st) {
      debugPrint('[TradeCreate] _loadAssetImages error: $e\n$st');
      if (mounted) {
        setState(() {
          _assetImageError = '자산 사진을 불러오지 못했어요. 직접 사진을 추가해주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingAssetImages = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked != null) {
      if (!mounted) return;
      setState(() {
        if (_photos.length >= _maxPhotos) return; // re-check after async gap
        _photos.add(_TradePhoto(file: File(picked.path), isAutoFilled: false));
        _selectedPhotoIndex = _photos.length - 1;
      });
    }
  }

  void _addPhoto() {
    if (_photos.length >= _maxPhotos) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: AppColors.blue,
              ),
              title: const Text(
                '카메라로 촬영',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.blue,
              ),
              title: const Text(
                '갤러리에서 선택',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
      _selectedPhotoIndex = null;
    });
  }

  Future<void> _submit() async {
    // 사진 1장 이상 필수 (feedback_hoga_design_invariants.md). RAW/PSA/BRG 동일.
    if (_photos.isEmpty) {
      _setInlineError('판매글 등록을 위해 실물 사진을 1장 이상 첨부해주세요.');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final priceText = _priceCtrl.text
          .trim()
          .replaceAll(',', '')
          .replaceAll('원', '');
      final price = int.tryParse(priceText);
      // 판매 가격 필수 (Phase 2: 가격 협의 폐지).
      if (price == null || price <= 0) {
        if (mounted) {
          setState(() {
            _submitting = false;
            _submitError = '판매 가격을 입력해주세요.';
          });
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(0,
                duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
          }
        }
        return;
      }
      // 말도 안 되는 가격 차단 (시장 교란 방지). 백엔드도 동일 강제(우회 방지).
      //  - GRADED: 예상가가 RAW 기준이라 부정확 → 검증 skip.
      //  - 금액대별 유동 밴드(저가 느슨 → 고가 ±50%). 예상가 없음: 절대 상한(1천만).
      if (_cardStatus != 'GRADED') {
        const ceiling = 10000000;
        final est = widget.defaultPrice;
        final bandable = est != null && est > 0;
        // 저가일수록 넓고 고가일수록 ±50% 로 좁아짐 (백엔드 priceBand 와 동일).
        double upMul, lowMul;
        if (est == null || est < 10000) { upMul = 5.0; lowMul = 0.2; }
        else if (est < 100000) { upMul = 3.0; lowMul = 0.4; }
        else if (est < 1000000) { upMul = 2.0; lowMul = 0.5; }
        else { upMul = 1.5; lowMul = 0.5; }
        final lower = bandable ? (est * lowMul).round() : 0;
        final upper = bandable ? (est * upMul).round() : ceiling;
        if (price < lower || price > upper) {
          if (mounted) {
            setState(() => _submitting = false);
            final msg = bandable
                ? '예상 시세 ${formatThousands(est)}원 기준\n'
                    '${formatThousands(lower)} ~ ${formatThousands(upper)}원 범위로 등록해 주세요.\n\n'
                    '시세와 크게 동떨어진 가격은 시장 교란 방지를 위해 등록할 수 없어요.'
                : '${formatThousands(ceiling)}원 이하로 등록해 주세요.\n\n'
                    '비정상적으로 높은 가격은 등록할 수 없어요.';
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.surfaceCard,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                title: const Text('등록할 수 없는 가격',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                content: Text(msg,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('확인', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }
      final memo = _memoCtrl.text.trim();
      final cardName = widget.cardName ?? widget.cardId;
      final description = memo.isNotEmpty
          ? memo
          : '[$cardName] $_cardStatus 판매';

      final createRes = await ApiClient.post('/api/trades', {
        'data': {
          'cardId': widget.cardId,
          if (widget.assetId != null && widget.assetId!.isNotEmpty)
            'assetId': widget.assetId,
          'description': description,
          'price': price,
          'cardStatus': _cardStatus,
          if (_condition != null) 'condition': _condition,
          if (_cardStatus == 'GRADED' && widget.gradingCompany != null)
            'gradingCompany': widget.gradingCompany,
          if (_cardStatus == 'GRADED' && widget.gradeValue != null)
            'gradeValue': widget.gradeValue,
          if (_cardStatus == 'GRADED' &&
              widget.certNumber != null &&
              widget.certNumber!.isNotEmpty)
            'certNumber': widget.certNumber,
        },
      });

      if (createRes['status'] != 'success') {
        throw Exception(createRes['message'] ?? '판매글 생성 실패');
      }
      final tradeId = createRes['data']?['tradeId'] as String?;
      if (tradeId == null) throw Exception('판매글 생성 실패');

      for (final photo in _orderedPhotosForUpload()) {
        if (!photo.file.existsSync()) continue;
        try {
          await ApiClient.uploadFile(
            '/api/trades/$tradeId/image',
            photo.file.path,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      debugPrint('등록 실패 원인: $e');
      // 백엔드 에러 메시지 보존 (E409 중복 판매 등) — Codex 즉시수정.
      String msg = '등록에 실패했어요. 잠시 후 다시 시도해주세요.';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['message'] is String) {
          msg = data['message'] as String;
        }
      }
      _setInlineError(msg);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  List<_TradePhoto> _orderedPhotosForUpload() {
    final frontPhotos = _photos.where((photo) => photo.imageType == 'FRONT');
    final backPhotos = _photos.where((photo) => photo.imageType == 'BACK');
    final otherPhotos = _photos.where(
      (photo) => photo.imageType != 'FRONT' && photo.imageType != 'BACK',
    );
    return [...frontPhotos, ...backPhotos, ...otherPhotos];
  }

  /// SnackBar 금지 정책 — inline error state 로 표시 + scroll-to-top.
  void _setInlineError(String msg) {
    if (!mounted) return;
    setState(() => _submitError = msg);
    // 사용자가 스크롤 하단에 있을 경우 inline error 가 뷰포트 밖이므로 최상단으로 이동.
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // sheet 모드: 키보드 시 Scaffold resize 대신 스크롤뷰가 입력칸 노출 (sheet 높이 깨짐 방지).
      resizeToAvoidBottomInset: widget.sheetScrollController == null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: widget.sheetScrollController ?? _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 매수 폼("이 가격에 사고 싶어요")과 동일 톤 — 헤더/닫기 아이콘 없이 바로 타이틀.
                    // 닫기는 바깥 탭(barrierDismissible)·시트 드래그로. 매수 폼에 없는 닫기 버튼 두지 않음.
                    const Text('판매글 등록',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('판매글을 올리면 구매 희망자에게 노출돼요.',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.5)),
                    const SizedBox(height: 14),
                    const TradeSafetyNotice(),
                    const SizedBox(height: 14),
            // 등록 실패 / 사진 누락 inline error (SnackBar 금지).
            if (_submitError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _submitError!,
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 카드 정보
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  CardImage(
                    imageUrl: widget.imageUrl,
                    width: 52,
                    height: 72,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.cardName ?? widget.cardId,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (widget.rarity != null && widget.rarity!.isNotEmpty)
                          Text(
                            widget.rarity!,
                            style: TextStyle(
                              color: AppColors.rarityColor(widget.rarity!),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 등급/상태 칩
                  _buildGradeChip(),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 사진
            Row(
              children: [
                const Text(
                  '카드 실물 사진',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '*',
                  style: TextStyle(
                    color: AppColors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${_photos.length}/$_maxPhotos)',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _cardStatus == 'GRADED'
                  ? '판매글 등록을 위해 사진 1장 이상 필수예요. 등급 카드는 슬랩과 라벨이 보이도록 촬영해주세요.'
                  : '판매글 등록을 위해 사진 1장 이상 필수예요.',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            // Phase 5: 자동첨부 진행 / 실패 안내.
            if (_loadingAssetImages) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.blue),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '자산 사진을 불러오는 중...',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
            if (_assetImageError != null) ...[
              const SizedBox(height: 6),
              Text(
                _assetImageError!,
                style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount:
                    _photos.length + (_photos.length < _maxPhotos ? 1 : 0),
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == _photos.length) {
                    return _buildAddPhotoTile();
                  }
                  return _buildPhotoThumbnail(index);
                },
              ),
            ),

            const SizedBox(height: 20),

            // 가격 (필수 — "가격 협의" 폐지: 호가창 ASK 쿼리는 price IS NOT NULL).
            Row(
              children: const [
                Text(
                  '가격',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  '*',
                  style: TextStyle(
                    color: AppColors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTextField(
              _priceCtrl,
              '판매 가격을 입력해주세요',
              keyboardType: TextInputType.number,
              suffix: '원',
              inputFormatters: [ThousandsCommaFormatter()],
            ),

            const SizedBox(height: 16),

            // 메모
            const Text(
              '메모',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '(선택) 짧게 남기고 싶은 말',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            _buildTextField(_memoCtrl, '예) 직거래 가능, 1회 슬리브 보관', maxLines: 3),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // 하단 고정 등록 버튼 — 매수 호가 등록 폼과 동일 패턴.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (!_submitting && _photos.isNotEmpty) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    // 판매(매도) 액션 = 파랑 (feedback_color_policy: 매수 빨강/매도 파랑, 토스식).
                    backgroundColor: AppColors.blue,
                    disabledBackgroundColor:
                        AppColors.blue.withValues(alpha: 0.35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('등록 중...',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ],
                        )
                      : const Text('판매글 등록하기',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradeChip() {
    if (_cardStatus == 'GRADED' &&
        widget.gradingCompany != null &&
        widget.gradeValue != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold.withOpacity(0.4)),
        ),
        child: Text(
          '${widget.gradingCompany} ${widget.gradeValue}',
          style: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }

    // Hotfix 10-1: AI 비활성 시 RAW estimatedGrade chip hide. GRADED (PSA) 만 표시.
    final condition = _condition;
    if (FeatureFlags.enableAiGrading && condition != null && widget.estimatedGrade != null) {
      final grade = widget.estimatedGrade!;
      final color = grade >= 9.0
          ? AppColors.green
          : grade >= 7.0
          ? AppColors.blue
          : AppColors.red;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(
              '앱분석 ${grade.toStringAsFixed(1)}점',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '컨디션: $condition',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'RAW',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPhotoThumbnail(int index) {
    final photo = _photos[index];
    final isSelected = _selectedPhotoIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPhotoIndex = isSelected ? null : index;
        });
      },
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                photo.file,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _removePhoto(index),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            if (photo.isAutoFilled)
              Positioned(
                left: 5,
                bottom: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'AUTO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddPhotoTile() {
    return GestureDetector(
      onTap: _addPhoto,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Icon(
          Icons.add_photo_alternate_rounded,
          color: AppColors.textMuted,
          size: 30,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
    String? suffix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.surfaceCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}
