import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_list_ui.dart';
import 'inquiry_category.dart';

/// 고객지원 — 문의 카테고리 분류 + 카테고리별 폼(/support/inquiry/:key) 진입점 + 내 문의 내역.
/// 2026-06-04: DB 문의로 전환 — 이메일 복사 제거(채널 혼란). 답변은 내 문의 내역에서 확인.
/// 2026-07-04: 토스 문법 통일 — AppGroupCard + AppMenuRow 허브형.
class CustomerSupportScreen extends StatelessWidget {
  const CustomerSupportScreen({super.key});

  Color _categoryColor(InquiryCategory c) {
    switch (c) {
      case InquiryCategory.cardAddRequest:
        return AppColors.blue;
      case InquiryCategory.priceError:
        return AppColors.green;
      case InquiryCategory.tradeChat:
        return AppColors.blueLight;
      case InquiryCategory.account:
        return AppColors.gold;
      case InquiryCategory.bug:
        return AppColors.red;
      case InquiryCategory.featureRequest:
        return AppColors.blue;
      case InquiryCategory.etc:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '고객지원',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '무엇을 문의하시나요?',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '문의 유형을 먼저 골라주세요. 카드 추가 요청은 사진을 함께 보내주시면 빠르게 처리됩니다.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const AppSectionLabel('문의 유형'),
            const SizedBox(height: 10),
            AppGroupCard(
              children: InquiryCategory.values
                  .map(
                    (c) => AppMenuRow(
                      icon: c.icon,
                      color: _categoryColor(c),
                      label: c.label,
                      subtitle: c.description,
                      onTap: () => context.push('/support/inquiry/${c.key}'),
                    ),
                  )
                  .toList(),
            ),
            // B2-20: '내 문의 내역' 은 MY 페이지에 직접 진입 메뉴가 있어 중복 → 여기서 제거.
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '평일 24~48시간 내 답변드립니다.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
