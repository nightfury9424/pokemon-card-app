import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';

/// 고객지원. App Review 5.1 — 작동하는 contact 정보 노출 + mailto 링크.
/// mailto가 동작 안 하는 환경(이메일 앱 미설치) 대비 이메일 주소 텍스트도 함께 노출.
class CustomerSupportScreen extends StatelessWidget {
  const CustomerSupportScreen({super.key});

  Future<void> _openMail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: ApiConstants.supportEmail,
      query: Uri.encodeQueryComponent('subject=[PokeFolio] 문의'),
    );
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (!context.mounted) return;
      // 메일 앱 없음 — 이메일 주소를 클립보드로 복사하고 안내.
      await Clipboard.setData(const ClipboardData(text: ApiConstants.supportEmail));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('메일 앱이 없어요. 이메일 주소를 복사했어요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await launchUrl(uri);
  }

  Future<void> _copyEmail(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: ApiConstants.supportEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이메일 주소를 복사했어요.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('고객지원',
            style: TextStyle(color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '문의하기',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '서비스 이용 중 불편하거나 궁금한 점이 있으면 아래 이메일로 문의해주세요. '
                '평일 24~48시간 내 답변드립니다.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '문의 이메일',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            ApiConstants.supportEmail,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _copyEmail(context),
                          icon: const Icon(Icons.copy_rounded,
                              color: AppColors.textSecondary, size: 18),
                          tooltip: '이메일 주소 복사',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _openMail(context),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: const Text('이메일로 문의하기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '문의 시 도움이 되는 정보',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '• 닉네임 또는 가입 이메일\n'
                '• 발생한 화면(스크린샷이 있으면 좋아요)\n'
                '• 발생 시각\n'
                '• 카드명·거래글 번호 등 관련 정보',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
