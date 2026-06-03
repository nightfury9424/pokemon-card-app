/// 온보딩 임시 입력 보존 — 앱 background/resume 또는 라우터 재계산으로 OnboardingScreen
/// State 가 재생성돼도 age 단계/닉네임/약관 체크가 유실되지 않게 위젯 밖 싱글톤에 들고 있음.
///
/// 가입 완료(_submit 성공) 또는 로그아웃 시 clear(). 같은 앱 세션(프로세스) 동안 유지.
class OnboardingDraft {
  OnboardingDraft._();
  static final OnboardingDraft instance = OnboardingDraft._();

  bool? ageOver14;        // null=미응답, true/false
  String nickname = '';
  bool agreedTos = false;
  bool agreedPrivacy = false;
  bool agreedScanImages = false;

  void clear() {
    ageOver14 = null;
    nickname = '';
    agreedTos = false;
    agreedPrivacy = false;
    agreedScanImages = false;
  }
}
