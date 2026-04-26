import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class TradeCreateScreen extends StatefulWidget {
  final String cardId;
  final String? cardName;
  final String? rarity;
  final String? imageUrl;

  const TradeCreateScreen({
    super.key,
    required this.cardId,
    this.cardName,
    this.rarity,
    this.imageUrl,
  });

  @override
  State<TradeCreateScreen> createState() => _TradeCreateScreenState();
}

class _TradeCreateScreenState extends State<TradeCreateScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  File? _pickedImage;
  bool _submitting = false;
  String _cardStatus = 'RAW';

  @override
  void initState() {
    super.initState();
    // 기본 제목 자동 입력
    if (widget.cardName != null) {
      _titleCtrl.text = widget.cardName!;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1080);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.blue),
              title: const Text('카메라로 촬영', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.blue),
              title: const Text('갤러리에서 선택', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack('제목을 입력해주세요');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _showSnack('본문을 입력해주세요');
      return;
    }
    if (_pickedImage == null) {
      _showSnack('카드 사진을 추가해주세요');
      return;
    }

    setState(() => _submitting = true);
    try {
      // 1. 판매글 생성
      final priceText = _priceCtrl.text.trim().replaceAll(',', '').replaceAll('원', '');
      final price = int.tryParse(priceText);

      final createRes = await ApiClient.post('/api/trades', {
        'data': {
          'cardId': widget.cardId,
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'price': price,
          'cardStatus': _cardStatus,
        }
      });

      final tradeId = createRes['data']?['tradeId'] as String?;
      if (tradeId == null) throw Exception('판매글 생성 실패');

      // 2. 이미지 업로드
      await ApiClient.uploadFile('/api/trades/$tradeId/image', _pickedImage!.path);

      if (!mounted) return;
      context.pop(true); // 성공 플래그와 함께 돌아감
    } catch (e) {
      _showSnack('등록 실패: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.surfaceElevated));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('판매글 등록', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2))
                : const Text('등록', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 카드 정보 표시
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
                        Text(widget.cardName ?? widget.cardId,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        if (widget.rarity != null && widget.rarity!.isNotEmpty)
                          Text(widget.rarity!,
                              style: TextStyle(color: AppColors.rarityColor(widget.rarity!), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 사진 업로드
            const Text('카드 실물 사진', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showImagePicker,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _pickedImage != null ? AppColors.blue : AppColors.divider,
                    width: _pickedImage != null ? 1.5 : 1,
                  ),
                ),
                child: _pickedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(_pickedImage!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded,
                              color: AppColors.textMuted, size: 48),
                          const SizedBox(height: 10),
                          const Text('사진 추가', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                          const SizedBox(height: 4),
                          const Text('카드 실물을 촬영하거나 갤러리에서 선택',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 20),

            // 카드 상태
            const Text('카드 상태', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStatusChip('RAW', 'RAW'),
                const SizedBox(width: 10),
                _buildStatusChip('GRADED', '그레이딩'),
              ],
            ),

            const SizedBox(height: 20),

            // 제목
            const Text('제목', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _buildTextField(_titleCtrl, '판매 제목을 입력하세요', maxLines: 1),

            const SizedBox(height: 16),

            // 가격
            const Text('가격', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _buildTextField(_priceCtrl, '가격 입력 (비우면 가격 협의)', maxLines: 1, keyboardType: TextInputType.number, suffix: '원'),

            const SizedBox(height: 16),

            // 본문
            const Text('본문', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _buildTextField(_descCtrl, '카드 상태, 구매 경위 등을 자유롭게 작성하세요', maxLines: 6),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String value, String label) {
    final selected = _cardStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _cardStatus = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.blue : AppColors.divider),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboardType, String? suffix}) {
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
