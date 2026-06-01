import 'package:flutter/material.dart';

/// 고객지원 문의 카테고리.
///
/// 베타 단계 정책 (A++ 프론트 전용):
///  - 카테고리만 7개로 분류, 카드 추가 요청 한정 구조화 필드, 나머지는 공통 자유 텍스트.
///  - 첨부 사진 최대 5장. flutter_email_sender 로 네이티브 메일 composer 호출.
///  - 백엔드/DB/admin/SMTP/S3 모두 베타 이후 별도 TF.
///
/// `key`는 라우터 경로 파라미터(`/support/inquiry/:key`)에 그대로 사용.
/// `subjectPrefix`는 메일 제목 자동 prefix (운영자가 inbox에서 분류).
enum InquiryCategory {
  cardAddRequest(
    key: 'card-add',
    label: '카드 추가 요청',
    subjectPrefix: '[카드 추가 요청]',
    description: 'DB에 없는 카드를 알려주세요. 카드 사진을 함께 보내주시면 더 빠르게 추가할 수 있어요.',
    isStructured: true,
    icon: Icons.add_card_outlined,
  ),
  priceError(
    key: 'price',
    label: '시세/가격 오류 신고',
    subjectPrefix: '[시세 오류]',
    description: '표시되는 시세가 실제와 다르거나 이상하면 알려주세요.',
    isStructured: false,
    icon: Icons.trending_up_outlined,
  ),
  tradeChat(
    key: 'trade',
    label: '거래/채팅 문의',
    subjectPrefix: '[거래/채팅]',
    description: '거래글, 채팅, 매도/매수 관련 문의.',
    isStructured: false,
    icon: Icons.swap_horiz_outlined,
  ),
  account(
    key: 'account',
    label: '계정/닉네임 문의',
    subjectPrefix: '[계정]',
    description: '닉네임 변경, 계정 복구 등 계정 관련 문의.',
    isStructured: false,
    icon: Icons.person_outline_rounded,
  ),
  bug(
    key: 'bug',
    label: '버그 신고',
    subjectPrefix: '[버그]',
    description: '앱이 멈추거나 오류가 발생했을 때.',
    isStructured: false,
    icon: Icons.bug_report_outlined,
  ),
  featureRequest(
    key: 'feature',
    label: '기능 제안',
    subjectPrefix: '[기능 제안]',
    description: '있으면 좋겠다 싶은 기능이 있다면 알려주세요.',
    isStructured: false,
    icon: Icons.lightbulb_outline_rounded,
  ),
  etc(
    key: 'etc',
    label: '기타 문의',
    subjectPrefix: '[기타]',
    description: '위 카테고리에 해당하지 않는 모든 문의.',
    isStructured: false,
    icon: Icons.help_outline_rounded,
  );

  const InquiryCategory({
    required this.key,
    required this.label,
    required this.subjectPrefix,
    required this.description,
    required this.isStructured,
    required this.icon,
  });

  final String key;
  final String label;
  final String subjectPrefix;
  final String description;
  final bool isStructured;
  final IconData icon;

  static InquiryCategory? fromKey(String? key) {
    if (key == null) return null;
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}
