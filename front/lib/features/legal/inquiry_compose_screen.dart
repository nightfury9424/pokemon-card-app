import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import 'inquiry_category.dart';

/// 카테고리별 문의 작성 화면.
///
/// 정책 (2026-06: 메일 → DB 전환):
///  - 카드 추가 요청 → 구조화 필드 (카드명/언어/세트명/카드번호/레어도/링크/추가설명).
///  - 그 외 카테고리 → 공통 자유 텍스트 1개.
///  - 제출 → POST /api/inquiries (DB 저장 → 관리자 페이지 처리). flutter_email_sender 폐기.
///  - 답변은 '신고/문의 내역'에서 확인 (관리자 답변 status).
///  - 사진 첨부(2026-06): 모든 카테고리 공통, 최대 5장. 문의 생성 후 inquiryId 로
///    multipart 업로드 (POST /api/inquiries/{id}/image — trade 패턴 재사용).
class InquiryComposeScreen extends StatefulWidget {
  final InquiryCategory category;
  const InquiryComposeScreen({super.key, required this.category});

  @override
  State<InquiryComposeScreen> createState() => _InquiryComposeScreenState();
}

class _InquiryComposeScreenState extends State<InquiryComposeScreen> {
  // 카드 추가 요청 필드
  final _cardName = TextEditingController();
  String _language = '한국판';
  final _setName = TextEditingController();
  final _cardNumber = TextEditingController();
  final _rarity = TextEditingController();
  final _refLink = TextEditingController();
  final _cardExtra = TextEditingController();
  // 공통 자유 텍스트
  final _freeText = TextEditingController();

  // 사진 첨부 (모든 카테고리 공통, 최대 5장)
  static const int _maxPhotos = 5;
  final List<XFile> _photos = [];

  bool _sending = false;
  String? _email;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final res = await ApiClient.get('/api/users/me');
      final data = res['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _email = data?['email'] as String?;
      });
    } catch (_) {
      // silent — 회신 이메일에만 쓰임. 실패해도 폼은 정상 동작.
    }
  }

  @override
  void dispose() {
    _cardName.dispose();
    _setName.dispose();
    _cardNumber.dispose();
    _rarity.dispose();
    _refLink.dispose();
    _cardExtra.dispose();
    _freeText.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    AppInfoToast.show(context, msg);
  }

  /// 본문 자동 생성 — 카드 추가 요청이면 구조화, 아니면 공통 자유 텍스트.
  /// 메타 footer(닉네임/시각/앱 버전) 자동 첨부.
  String _buildContent() {
    final cat = widget.category;
    final buf = StringBuffer();
    if (cat == InquiryCategory.cardAddRequest) {
      buf.writeln('[카드 추가 요청]');
      buf.writeln('카드명: ${_cardName.text.trim()}');
      buf.writeln('언어: $_language');
      buf.writeln('수록팩/세트명: ${_setName.text.trim()}');
      buf.writeln('카드 번호: ${_cardNumber.text.trim()}');
      buf.writeln('레어도: ${_rarity.text.trim()}');
      buf.writeln('참고 링크: ${_refLink.text.trim()}');
      buf.writeln('추가 설명:');
      buf.writeln(_cardExtra.text.trim());
    } else {
      buf.write(_freeText.text.trim());
    }
    // 메타(닉네임/시각/버전) footer 제거 — admin 에 userId/작성일 컬럼 별도 존재, content 깔끔하게.
    return buf.toString().trim();
  }

  String _buildTitle() {
    final cat = widget.category;
    if (cat == InquiryCategory.cardAddRequest) {
      final name = _cardName.text.trim();
      return name.isEmpty ? '카드 추가 요청' : '카드 추가 요청: $name';
    }
    return cat.label;
  }

  bool _validate() {
    if (widget.category == InquiryCategory.cardAddRequest) {
      if (_cardName.text.trim().isEmpty) {
        _toast('카드명을 입력해주세요.');
        return false;
      }
      if (_setName.text.trim().isEmpty) {
        _toast('수록팩/세트명을 입력해주세요.');
        return false;
      }
    } else {
      if (_freeText.text.trim().isEmpty) {
        _toast('문의 내용을 입력해주세요.');
        return false;
      }
    }
    return true;
  }

  Future<void> _send() async {
    if (_sending) return;
    if (!_validate()) return;
    setState(() => _sending = true);
    try {
      final res = await ApiClient.post('/api/inquiries', {
        'data': {
          'category': widget.category.key,
          'title': _buildTitle(),
          'content': _buildContent(),
          if (_email != null && _email!.isNotEmpty) 'contactEmail': _email,
        },
      });
      if (!mounted) return;
      if (res['status'] != 'success') {
        setState(() => _sending = false);
        AppErrorToast.show(
            context,
            (res['message'] is String &&
                    (res['message'] as String).trim().isNotEmpty)
                ? res['message'] as String
                : '문의 접수에 실패했어요. 잠시 후 다시 시도해주세요.');
        return;
      }
      // 사진 첨부 — 문의 생성 후 inquiryId 로 multipart 업로드 (trade 패턴).
      // 본문은 이미 접수됐으므로 사진 일부 실패해도 문의는 성공 처리, 실패 건수만 안내.
      final inquiryId = res['data']?['inquiryId'] as String?;
      int imgFail = 0;
      if (inquiryId != null && _photos.isNotEmpty) {
        for (final photo in _photos) {
          try {
            await ApiClient.uploadFile(
                '/api/inquiries/$inquiryId/image', photo.path);
          } catch (_) {
            imgFail++;
          }
        }
      }
      if (!mounted) return;
      setState(() => _sending = false);
      if (imgFail > 0) {
        AppInfoToast.show(
            context, '문의는 접수됐지만 사진 $imgFail장은 업로드에 실패했어요.');
      } else {
        AppSuccessToast.show(
            context, '문의가 접수됐어요. 답변은 문의 내역에서 확인할 수 있어요.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // 5-1: 제출 후 고객지원(카테고리)으로 안 돌아가고 내 문의 내역으로 — 방금 보낸 문의+상태 바로 보이게.
      if (mounted) context.pushReplacement('/profile/inquiries');
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      AppErrorToast.show(context, '문의 접수에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(cat.label,
            style: const TextStyle(color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.description,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13, height: 1.55),
                    ),
                    const SizedBox(height: 16),
                    if (cat == InquiryCategory.cardAddRequest)
                      _buildCardAddFields()
                    else
                      _buildFreeTextField(),
                    const SizedBox(height: 20),
                    _buildPhotoSection(),
                  ],
                ),
              ),
            ),
            _buildSendBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCardAddFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('카드명', required: true),
        _textField(_cardName, hint: '예: 마리오 피카츄'),
        const SizedBox(height: 14),
        _label('언어', required: true),
        Wrap(
          spacing: 8,
          children: ['한국판', '일본판', '영어판'].map((lang) {
            final sel = _language == lang;
            return ChoiceChip(
              label: Text(lang),
              selected: sel,
              onSelected: (v) {
                if (v) setState(() => _language = lang);
              },
              selectedColor: AppColors.blue,
              backgroundColor: AppColors.surfaceCard,
              labelStyle: TextStyle(
                color: sel ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(color: sel ? AppColors.blue : AppColors.divider),
              showCheckmark: false,
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        _label('수록팩 / 세트명', required: true),
        _textField(_setName, hint: '예: 스칼렛 ex / SV5K'),
        const SizedBox(height: 14),
        _label('카드 번호'),
        _textField(_cardNumber, hint: '예: 296/SV-P'),
        const SizedBox(height: 14),
        _label('레어도'),
        _textField(_rarity, hint: '예: PR / SAR / SR'),
        const SizedBox(height: 14),
        _label('참고 링크'),
        _textField(_refLink, hint: '판매처/카탈로그 URL 등'),
        const SizedBox(height: 14),
        _label('추가 설명'),
        _textField(_cardExtra, hint: '특이사항이 있으면 적어주세요.', maxLines: 4),
      ],
    );
  }

  Widget _buildFreeTextField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('문의 내용', required: true),
        _textField(_freeText,
            hint: '발생한 화면, 시각, 재현 방법 등을 적어주시면 빠르게 도와드릴 수 있어요.',
            maxLines: 8),
      ],
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('사진 첨부'),
        const Text(
          '사진은 필수는 아니지만, 없으면 확인이 늦거나 처리가 어려울 수 있어요.\n'
          '문제 화면·카드 사진을 함께 보내주시면 더 빠르게 도와드릴 수 있어요. (최대 5장)',
          style: TextStyle(
              color: AppColors.textMuted, fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (int i = 0; i < _photos.length; i++) _photoThumb(i, _photos[i]),
            if (_photos.length < _maxPhotos) _addPhotoButton(),
          ],
        ),
      ],
    );
  }

  Widget _photoThumb(int index, XFile photo) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(photo.path),
            width: 84,
            height: 84,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: _sending
                ? null
                : () => setState(() => _photos.removeAt(index)),
            child: Container(
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(3),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addPhotoButton() {
    return GestureDetector(
      onTap: _sending ? null : _showPhotoPicker,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined,
                size: 22, color: AppColors.textSecondary),
            const SizedBox(height: 4),
            Text('${_photos.length}/$_maxPhotos',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _showPhotoPicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.textPrimary),
              title: const Text('카메라로 촬영',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.textPrimary),
              title: const Text('갤러리에서 선택',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickPhoto(source);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() => _photos.add(picked));
    } catch (_) {
      if (!mounted) return;
      AppErrorToast.show(context, '사진을 불러오지 못했어요.');
    }
  }

  Widget _buildSendBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.dividerSoft)),
      ),
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_sending ? '접수 중...' : '문의 보내기'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blue,
            disabledBackgroundColor: AppColors.divider,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  /// 필수 표시 — 빨강이 아닌 blueLight (양·음 색 정책상 빨강은 음수 시그널 전용).
  Widget _label(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          text: text,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800),
          children: [
            if (required)
              const TextSpan(
                  text: ' *',
                  style: TextStyle(color: AppColors.blueLight)),
          ],
        ),
      ),
    );
  }

  Widget _textField(TextEditingController ctrl,
      {String? hint, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        filled: true,
        fillColor: AppColors.surfaceCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
        ),
      ),
    );
  }
}
