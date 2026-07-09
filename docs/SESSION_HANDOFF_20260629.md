# ★★ 마스터 세션 핸드오프 (2026-06-29) — 출시 3트랙 병렬

> **새 세션 첫 진입점.** iOS·Android·SNK 3트랙이 병렬 → 헷갈리지 말 것. 각 트랙 진입문서는 하단.

## 현재 상태 (한눈에)
| 트랙 | 상태 | 내가(Claude) | 너(사용자) |
|---|---|---|---|
| **iOS 1.0.4 (게시판)** | ✅ **심사 제출됨 · "심사 대기 중"** (build 202606280254) | 끝 (대기) | Apple 심사 결과 기다림 |
| **Android 1.0.4** | 코드/서명/AAB 완료·원격push, **Play Console 막힘** | 코드 끝 (대기) | Play 신원인증→앱생성→AAB업로드→앱서명SHA→Firebase |
| **SNK 가격 파이프라인** | 닫힘 (분석·설계 완료, 구현 deferred) | 설계 끝 | 별도 세션에서 재개 |

## ★★ iOS ↔ Android 헷갈리지 마 (둘 다 버전 1.0.4 · 같은 패키지 `com.fury.pokemoncardapp`)
| 구분 | **iOS** | **Android** |
|---|---|---|
| 빌드번호 | **202606280254** (타임스탬프) | **versionCode 4** |
| 브랜치 | `integ/board-release-1.0.4` | `feat/android-release` (원격 push됨) |
| 서명 | Apple 인증서(`~/pem/*.p8/.pem`) | keystore `~/pem/pokefolio-upload.jks`(alias pokefolio) |
| 산출물 | IPA `~/Downloads/pokefolio_1.0.4_202606280254_pencil.ipa` (arm64) | AAB `front/build/app/outputs/bundle/release/app-release.aab` |
| 업로드 | Transporter → App Store Connect | Play Console |
| 빌드 명령 | `flutter build ipa` + 타임스탬프 build-number + prod BASE_URL | `flutter build appbundle --release --build-name=1.0.4 --build-number=4` |
| 상태 | **심사 제출됨(대기 중)** | **미제출** (Play 계정 인증 대기) |
| Firebase SHA | iOS는 APNs (SHA 불필요) | release SHA 등록됨 + **첫 업로드 후 Play앱서명SHA 추가 필요** |

**공통 주의:** pubspec은 `1.0.1+3`(stale) — 둘 다 빌드 명령/timestamp로 버전 override. **pubspec 수정 금지**(iOS 빌드번호 보호).

## 트랙별 진입 문서
- **iOS(게시판)**: 이 문서 + 상세 `docs/SESSION_HANDOFF_20260627.md` / 검증·기능 `project_board_view_notify_20260627`(메모리). 게시판 코드=`integ/board-release-1.0.4`. 금칙어 모더레이션 **prod 활성 확인됨**(ContentPolicyService 배포·banned_words 로드·profile=prod·신고/차단/admin). 심사정보 데모=Apple로그인 자가가입+전화인증 테스트번호 010-1234-5678/123456.
- **Android**: `docs/ANDROID_RELEASE_HANDOFF_20260628.md`. keystore 백업필수. release SHA-1 `78:C6:8A..`. google-services.json gitignore.
- **SNK**: `docs/SNK_PRICE_PIPELINE_DESIGN.md` + 복붙용 `docs/SNK_HANDOFF_PASTE_20260629.md`. **운영반영 0·구현 전.** working 매핑 3,313(≠approved).

## 다음 (우선순위)
1. **iOS** = Apple 심사 결과 대기 (반려 시 회신, 승인 시 출시 — 출시옵션 수동이면 네가 버튼).
2. **Android** = Play Console 신원인증 풀리면 진행 (너).
3. **SNK** = 보류 (다음 세션, 복붙 핸드오프).

## 금지 / 주의
- iOS·Android 작업 섞지 말 것 (브랜치·빌드번호·서명 다름).
- pubspec.yaml 수정 금지.
- SNK 가격 운영반영·DB write·prod write 금지 (read-only도 승인 먼저).
- prod 직접 수정 금지 (백업+승인 후).
