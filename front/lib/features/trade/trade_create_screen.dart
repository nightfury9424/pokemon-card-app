import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

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
  final String? cdnImageUrl;
  final String? assetId;
  final String? cardStatus;
  final double? estimatedGrade;
  final String? gradingCompany;
  final String? gradeValue;
  final String? certNumber;
  final int? defaultPrice;

  const TradeCreateScreen({
    super.key,
    required this.cardId,
    this.cardName,
    this.rarity,
    this.imageUrl,
    this.cdnImageUrl,
    this.assetId,
    this.cardStatus,
    this.estimatedGrade,
    this.gradingCompany,
    this.gradeValue,
    this.certNumber,
    this.defaultPrice,
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
      _priceCtrl.text = widget.defaultPrice!.toString();
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

        final response = await Dio().get<List<int>>(
          fullUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.statusCode == 200 && response.data != null) {
          final type = imageType.toLowerCase();
          final docsDir = await getApplicationDocumentsDirectory();
          final tempFile = File('${docsDir.path}/asset_${type}_$assetId.jpg');
          await tempFile.writeAsBytes(response.data!);
          autoPhotos.add(
            _TradePhoto(
              file: tempFile,
              isAutoFilled: true,
              imageType: imageType,
            ),
          );
        } else {
          debugPrint('[TradeCreate] _loadAssetImages — $imageType download fail status=${response.statusCode}');
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
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          '판매글 등록',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Builder(builder: (_) {
            // 사진 1장 이상 + 등록 중 아닐 때만 활성 (정책).
            final canSubmit = !_submitting && _photos.isNotEmpty;
            return TextButton(
              onPressed: canSubmit ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: AppColors.blue,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      '등록',
                      style: TextStyle(
                        color: canSubmit
                            ? AppColors.blue
                            : AppColors.blue.withValues(alpha: 0.35),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            );
          }),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    cdnFallbackUrl: widget.cdnImageUrl,
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

            const SizedBox(height: 40),
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

    final condition = _condition;
    if (condition != null && widget.estimatedGrade != null) {
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
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
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
