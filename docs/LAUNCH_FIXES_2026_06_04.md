# 출시 전 수정 리스트 (2026-06-04)

> 하나씩 쳐낸다. 체크박스 = 완료. 각 항목 **증상 / 목표 / 파일힌트 / 범위**.
> 원칙: 이번 버그 배치는 **Flutter front 중심**. backend/scanner/grading/DB 마이그는 섞지 말 것(별도). 거래상태/채팅/신고/차단 로직 건드리지 말 것.

---

## 🔴 P0 — 심사 제출 전 필수

### [ ] 1. 온보딩 중 앱 이탈→복귀 시 상태 초기화 (★영상 확인 신규)
- **증상**: 만14세 선택 → 닉네임 입력 → 약관 체크(시작하기 활성) 상태에서 앱 백그라운드 갔다 복귀하면 **"만 14세 이상이신가요?" 화면으로 리셋** + 닉네임/체크 유실. (전화인증·문자확인 때문에 앱 밖에 나갈 일 많음 → 치명적)
- **목표**: background/foreground 전환(앱 kill 아님)에선 age-confirmed/nickname/약관체크 상태 **유지**. 완전 종료 시에만 초기화 허용.
- **확인 원인**: ①resume 시 auth/bootstrap 라우터 재계산이 onboarding을 age step으로 초기화하는지 ②OnboardingScreen dispose/recreate로 local state 날아가는지 ③redirect가 resume 때 다시 /onboarding 첫 step으로 보내는지.
- **수정 방향**: 온보딩 step/nickname/terms를 단순 local 변수 → 상위 state(ChangeNotifier/StateNotifier 등) 또는 세션 보존. "시작하기" 성공 전엔 임시 state만, 서버 가입완료 처리 X.
- **파일**: `front/lib/features/auth/onboarding_screen.dart`, `front/lib/core/router/app_router.dart`, `AuthState`.

### [ ] 2. 탈퇴 계정 재로그인 버그 + 30일 정책
- **증상**: 계정 삭제 후 같은 소셜로 재로그인하면 **"탈퇴한 사용자 #58B680"인 채로 로그인돼버림**(Image). 차단/안내 없음.
- **목표(정책)**:
  - 탈퇴 = **즉시 비활성화(soft-delete) + 30일 뒤 완전 삭제**(스케줄 hard-delete).
  - **★탈퇴 실행 시점에 "탈퇴 후 30일간 재가입할 수 없습니다" 안내(확인 다이얼로그) 필수.** 동의해야 탈퇴 진행.
  - 탈퇴 후 30일 내 같은 소셜 재로그인 → **차단 + "30일 후 재가입 가능" 안내**(로그인되면 안 됨 — 현재 "탈퇴한 사용자"로 로그인되는 게 버그).
  - 30일 보존 이유: 데이터/분쟁 대응 + 즉시 재가입 악용 방지.
- **범위**: 백엔드 auth 로그인 플로우(deletedAt 체크 → 거부/안내) + 30일 hard-delete 잡. **(별도 backend 작업 — 프론트 버그 배치와 분리)**
- **파일**: `back .../auth` 로그인, `DeletedUserGuardFilter`, `UserService` 탈퇴, 스케줄러.

---

## 🟠 P1 — 출시 전 권장

### [ ] 3. 프로필 편집 (프로필 카드 탭 → 닉네임 + 프로필 사진 변경)
- **증상**: 닉네임 변경이 "계정 > 닉네임 변경" 별도 메뉴에만 있음. 프로필 사진 변경 기능 **없음**(아마).
- **목표**: MY 상단 **프로필 카드 탭 → 프로필 편집 화면**(닉네임 변경 + **프로필 이미지 업로드/변경**). "닉네임 변경" 별도 메뉴는 제거(또는 편집화면으로 통합).
- **범위**: 프론트(편집 화면) + 백엔드(프로필 이미지 업로드 endpoint 있는지 확인 — 없으면 추가). **이미지 업로드는 IPA + 백엔드 필요.**
- **파일**: `front/lib/features/profile/profile_screen.dart`, `edit_nickname_screen.dart`(→ 편집화면으로 확장), `UserController`.

### [ ] 4. 프로필 카드에서 이메일 제거 + stat에 "구매중" 추가
- **증상**: 프로필 카드에 이메일(`...@privaterelay.appleid.com`) 노출 → **빼야 함**.
- **목표**: 프로필 카드 = 아바타 + 닉네임만(이메일 X). 이메일 자리엔 stat 등 다른 정보. **stat 행에 "구매중"(OPEN 매수 호가 수) 추가** → 보유카드 / 판매중 / **구매중** 3종.
- **파일**: `front/lib/features/profile/profile_screen.dart`.

### [ ] 5. 문의(Inquiry) 플로우 개선
- **5-1** 제출 후 → 고객지원(카테고리) 화면으로 돌아감. **"내 문의 내역"으로 이동**시켜 방금 보낸 문의+상태 보이게.
- **5-2** "문의하기"와 "내 문의 내역"이 MY 별개 메뉴 → **한 화면 통합**([새 문의]+[내 문의 목록]).
- **5-3** 고객지원 상단 **"이메일 복사" 제거**(DB 문의로 전환됨, 불필요 + 채널 혼란).
- **5-4** 관리자 답변 시 **`INQUIRY_ANSWERED` 알림**(푸시+인앱) — NotificationService 이미 있어 쉬움. (백엔드)
- **파일**: `front .../legal/{customer_support_screen,inquiry_compose_screen}`, `profile/inquiry_history_screen`, `back .../inquiry/InquiryAdminController`(답변 시 notify).

### [ ] 6. 홈 로딩 여전히 느림 재검증
- **증상**: 홈 진입 시 전체 스피너가 여전히 오래 도는 것으로 보임(시장/거래 API 묶음이 끝나야 화면 뜨는 구조 잔존 가능).
- **목표**: Scaffold/상단/섹션 컨테이너 즉시 렌더. top/hot/gainer/recent-trade/assets/portfolio **각 섹션 독립 로딩 + skeleton**. 카드 이미지 로딩이 전체 렌더 막지 않게(placeholder/errorWidget만).
- **파일**: `front/lib/features/home/home_screen.dart`. (이전 점진렌더 + 캐러셀 fix 했으나 재확인 필요)

---

## ⚪ 정책 결정 필요

### [x] 7. 같은 번호 다른 소셜계정 인증 → **봐주자(차단 X) — 결정 완료**
- 결정: 구글로 번호 인증 후 다른 애플 아이디로 **같은 번호 인증해도 허용**(차단 X). 이미 다른 아이디로 로그인해 전번 인증하는 중 막히면 **흐름상 이상**하니까.
- 함의: `findByPhoneE164AndPhoneVerifiedTrue` "번호당 1 인증계정" 가드가 재인증을 막으면 **완화**(새 계정으로 인증 시 기존 보유 해제/이전 허용). 탈퇴 30일 보존과 무관하게 번호 인증은 관대하게.
- 범위: 백엔드 전화인증 — 이번 프론트 버그 배치와 분리.

---

## 🔁 회귀 재검증 (이미 수정, 빌드에서 확인)
- [ ] 판매글/매수 호가 등록 sheet UI 통일(chevron/헤더 제거, 매수폼과 동일 톤) — `trade_create_screen.dart` (수정됨)
- [ ] 매수 호가 가격 기본값 = 현재 시세 반올림(0원 아님) — `card_detail_screen.dart` `_roundTo100` (수정됨)
- [ ] 홈 캐러셀 카드 2장 부드러움(느림 없음) — (수정됨)

---

## ✅ 완료 — prod/IPA 배포만 대기
- [x] 신고/제재: resolutionAction 실제 실행(P0) + **경고 누적→자동정지**(3회) — `ee21e8fe`. **prod 미배포(V20260604 마이그 수동적용 필요).**
- [x] 호가 시트: 403 친절메시지 / "준비중" 삭제 / 아바타 프로필 통일 / 색반전 정정 — `b3d8d48c`,`086a5057`
- [x] 관심 목록 2탭(게시물+관심카드) — `ccea122a`
- [x] 온보딩 약관/개인정보 "보기" 링크 열람 허용 — `dd44303a` (다음 IPA 확인)
- [x] 전화인증 작동(DB 확인) / 캐러셀 / 보안·DoS / 스캔 동의 게이팅 등

---

## 🔵 Post-launch (분리)
- [ ] 스캐너 캡처 활성 검증 + 첫 모델 학습(맥 agent) + SCANNER 토큰 .env + compose :rw
- [ ] 문의 이미지 첨부(S3 multipart)
- [ ] admin `/stats/scans` 실제 연동(현재 0 stub)
- [ ] 국내 실거래 가격 라벨(DOMESTIC_*) domesticCount 배선

---

## 📦 다음 배포 묶음 (커밋되어 있으나 미배포)
- 백엔드: `ee21e8fe`(모더레이션, +V20260604 마이그) — push+pull+rebuild back, 마이그 수동 적용.
- 프론트(다음 IPA): `dd44303a`(온보딩 약관링크) + 위 P0/P1 수정분.
