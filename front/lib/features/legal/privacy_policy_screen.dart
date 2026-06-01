import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';

/// 개인정보처리방침. App Review 5.1 필수 + PokeFolio 실제 수집/처리 항목 반영.
/// 정식 운영 전 개인정보보호책임자/사업자 정보는 별도 갱신 필요.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = '''제1조 (수집하는 개인정보 항목)
PokeFolio는 다음 항목을 수집·이용합니다.

[필수 수집]
- Google 로그인 식별자(googleId)
- 이메일 주소
- 닉네임 (이용자 직접 입력)

[선택 수집]
- 프로필 이미지

[서비스 이용 과정에서 자동 생성]
- 보유 카드 자산 정보 (사용자가 등록한 카드 정보)
- 판매글·매수글 내역 (가격, 카드 상태, 메모, 사진)
- 채팅 메시지 (다른 이용자와의 거래 협상)
- 신고 내역 (사용자 신고 활동)
- 차단한 사용자 목록
- 카드 스캔 시 촬영된 이미지 (AI 인식·그레이딩 분석용)
- 그레이딩 분석 요청 데이터 및 결과
- 앱 이용 로그 (접속 시각, 페이지 이동, 호가 등록 이력)
- 기기 정보 (OS, 앱 버전)

제2조 (개인정보의 수집·이용 목적)
1. 회원 식별 및 인증 (Google OAuth)
2. 거래·호가·시세 등 서비스 기능 제공
3. AI 카드 인식·그레이딩 분석 결과 제공
4. 시세·통계 분석 (비식별 처리 후)
5. 부정 이용·사기 방지 (신고/차단/탈퇴 기록 보존)
6. 분쟁 대응 및 운영 (채팅·거래 기록 보존)
7. 고객 문의 응대

제3조 (개인정보의 보유·이용 기간)
1. 회원 정보: 회원 탈퇴 시까지. 단, 아래 항목은 탈퇴 후에도 일정 기간 보존됩니다.
   - 거래 기록(판매글·매수글·채팅): 분쟁 대응 목적 (관련 법령에 따라 최대 5년)
   - 신고 기록: 사기·악용 패턴 추적 목적 (관련 법령에 따라 보존)
   - 부정 이용 기록: 재가입 차단 목적 (관련 법령에 따라 최대 1년)
2. 탈퇴 시 즉시 마스킹되는 항목: 이메일, 닉네임(→ "탈퇴한 사용자 #익명코드"), 프로필 이미지.
3. 법령(전자상거래법, 통신비밀보호법 등)에서 보존 의무를 정한 경우 해당 기간 동안 보존합니다.

제4조 (개인정보의 제3자 제공)
회사는 이용자의 개인정보를 외부에 제공하지 않습니다. 단, 다음 경우는 예외입니다.
- 이용자가 사전에 동의한 경우
- 법령에 의거하거나 수사기관의 적법한 요청이 있는 경우

제5조 (개인정보 처리 위탁)
원활한 서비스 제공을 위해 일부 업무를 외부 업체에 위탁할 수 있습니다.
- Google LLC: OAuth 로그인 인증
- AWS (Amazon Web Services): 서버·데이터 저장 (Lightsail Seoul region)
- Apple Inc.: TestFlight·App Store를 통한 앱 배포

제6조 (개인정보의 파기 절차 및 방법)
1. 파기 대상: 보유 기간이 경과한 개인정보.
2. 파기 방법:
   - 전자적 파일: 복구 불가능한 방법으로 영구 삭제
   - 종이 문서: 분쇄기로 분쇄 또는 소각
3. 탈퇴 즉시 마스킹되는 PII는 별도 파기 절차 없이 application 레벨에서 null/익명코드로 덮어씁니다.

제7조 (이용자의 권리)
이용자는 언제든지 다음 권리를 행사할 수 있습니다.
- 개인정보 열람 요구
- 개인정보 정정·삭제 요구
- 개인정보 처리정지 요구
- 회원 탈퇴 (앱 내 MY → 계정 삭제)
권리 행사는 앱 내 메뉴 또는 아래 고객지원 이메일로 요청해주세요.

제8조 (개인정보의 안전성 확보 조치)
1. 기술적 조치: HTTPS 통신 암호화, 비밀번호 일방향 해시 저장, 권한별 접근 통제.
2. 관리적 조치: 개인정보 접근 권한 최소화, 정기 보안 점검.
3. 물리적 조치: AWS 데이터센터 보안 정책 준수.

제9조 (카드 스캔·AI 분석 데이터 처리)
1. 카드 스캔 시 촬영된 이미지는 카드 인식·시세 매칭 목적으로만 처리됩니다.
2. 그레이딩 분석 데이터는 분석 결과 제공 목적 외 별도로 활용되지 않습니다.
3. 비식별 처리된 통계는 서비스 품질 개선(시세 모델 학습 등)에 활용될 수 있습니다.

제10조 (개인정보 보호책임자 및 문의)
- 개인정보 보호책임자: 운영팀
- 문의 이메일: ${ApiConstants.supportEmail}

제11조 (방침의 변경)
본 방침은 법령·정책 변경 또는 보안 기술 변경에 따라 개정될 수 있습니다. 변경 시 앱 공지사항을 통해 시행 7일 전 안내합니다.

부칙
본 방침은 2026년 5월 28일부터 시행합니다.''';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('개인정보처리방침',
            style: TextStyle(color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: SelectableText(
            content,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}
