import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import 'inquiry_category.dart';

/// 카테고리별 문의 작성 화면.
///
/// 정책 (베타 A++ 프론트 전용):
///  - 카드 추가 요청 → 구조화 필드 (카드명/언어/세트명/카드번호/레어도/링크/추가설명).
///  - 그 외 카테고리 → 공통 자유 텍스트 1개.
///  - 사진 첨부 최대 5장 (image_picker 다중 선택 + 카메라 단발 가능).
///  - 제출 → flutter_email_sender 네이티브 composer 호출 (subject/body/첨부 미리 채워짐).
///  - 메일 앱 미설정 시 fallback: 본문 클립보드 복사 또는 mailto(첨부 없이) 시도.
///  - 백엔드 호출은 닉네임 fetch(/api/users/me) 한 건뿐 — DB 저장/admin/SMTP 없음.
class InquiryComposeScreen extends StatefulWidget {
  final InquiryCategory category;
  const InquiryComposeScreen({super.key, required this.category});

  @override
  State<InquiryComposeScreen> createState() => _InquiryComposeScreenState();
}

class _InquiryComposeScreenState extends State<InquiryComposeScreen> {
  static const int _maxImages = 5;

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

  final List<XFile> _images = [];
  bool _sending = false;
  String? _nickname;

  @override
  void initState() {
    super.initState();
    _loadNickname();
  }

  Future<void> _loadNickname() async {
    try {
      final res = await ApiClient.get('/api/users/me');
      final data = res['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() => _nickname = data?['nickname'] as String?);
    } catch (_) {
      // silent — 메타 footer에만 쓰임. 실패해도 폼은 정상 동작.
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

  Future<void> _pickFromGallery() async {
    if (_images.length >= _maxImages) {
      _toast('사진은 최대 $_maxImages장까지 첨부할 수 있어요.');
      return;
    }
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(imageQuality: 80);
      if (picked.isEmpty) return;
      setState(() {
        for (final f in picked) {
          if (_images.length < _maxImages) _images.add(f);
        }
      });
    } catch (e) {
      _toast('사진을 가져오지 못했어요.');
    }
  }

  Future<void> _pickFromCamera() async {
    if (_images.length >= _maxImages) {
      _toast('사진은 최대 $_maxImages장까지 첨부할 수 있어요.');
      return;
    }
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (shot == null) return;
      setState(() => _images.add(shot));
    } catch (e) {
      _toast('카메라를 열 수 없어요.');
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 본문 자동 생성 — 카드 추가 요청이면 구조화, 아니면 공통 자유 텍스트.
  /// 항상 메타 footer 자동 첨부 (닉네임/시각/앱 버전).
  String _buildBody() {
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
      buf.writeln('[${cat.label}]');
      buf.writeln('문의 내용:');
      buf.writeln(_freeText.text.trim());
    }
    buf.writeln('');
    buf.writeln('─────────');
    buf.writeln('닉네임: ${_nickname ?? '(불러오기 실패)'}');
    buf.writeln('작성 시각: ${DateTime.now().toIso8601String()}');
    buf.writeln('앱 버전: PokeFolio 1.0 (베타)');
    return buf.toString();
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

    final subject = '[PokeFolio] ${widget.category.subjectPrefix}';
    final body = _buildBody();
    final attachments = _images.map((x) => x.path).toList();

    final email = Email(
      body: body,
      subject: subject,
      recipients: [ApiConstants.supportEmail],
      attachmentPaths: attachments,
      isHTML: false,
    );

    try {
      await FlutterEmailSender.send(email);
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('메일 앱이 열렸어요. 보내기를 눌러주세요.');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      await _showFallbackDialog(subject: subject, body: body);
    }
  }

  /// 메일 composer 미작동 fallback — 본문 복사 / mailto(첨부 없이) 시도 / 안내.
  Future<void> _showFallbackDialog({required String subject, required String body}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('이메일 앱이 설정되지 않았어요',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
        content: const Text(
          '본문을 복사해서 메일 앱이나 웹메일에서 직접 보내주세요.\n'
          '사진은 별도로 직접 첨부해야 합니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: '제목: $subject\n\n$body'));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _toast('본문을 복사했어요. 이메일 앱에 붙여넣어 주세요.');
            },
            child: const Text('본문 복사', style: TextStyle(color: AppColors.blueLight, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _tryMailtoFallback(subject, body);
            },
            child: const Text('메일로 시도', style: TextStyle(color: AppColors.blueLight, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _tryMailtoFallback(String subject, String body) async {
    final uri = Uri(
      scheme: 'mailto',
      path: ApiConstants.supportEmail,
      query: 'subject=${Uri.encodeQueryComponent(subject)}&body=${Uri.encodeQueryComponent(body)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _toast('메일 앱이 없어요. 본문을 복사해서 직접 보내주세요.');
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
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.55),
                    ),
                    const SizedBox(height: 16),
                    if (cat == InquiryCategory.cardAddRequest)
                      _buildCardAddFields()
                    else
                      _buildFreeTextField(),
                    const SizedBox(height: 20),
                    _buildAttachmentSection(),
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

  Widget _buildAttachmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('사진 첨부',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Text('${_images.length}/$_maxImages',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '메일 composer에서 첨부 상태로 열립니다.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._images.asMap().entries.map((e) => _buildThumb(e.key, e.value)),
            if (_images.length < _maxImages)
              _buildAddBtn(
                  icon: Icons.photo_library_outlined,
                  label: '갤러리',
                  onTap: _pickFromGallery),
            if (_images.length < _maxImages)
              _buildAddBtn(
                  icon: Icons.camera_alt_outlined,
                  label: '카메라',
                  onTap: _pickFromCamera),
          ],
        ),
      ],
    );
  }

  Widget _buildThumb(int index, XFile file) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(file.path),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => _removeImage(index),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
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
              : const Icon(Icons.mail_outline_rounded, size: 18),
          label: Text(_sending ? '메일 앱 여는 중...' : '메일로 보내기'),
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
