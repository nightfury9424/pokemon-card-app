# ANDROID RELEASE HANDOFF (2026-06-28)

> 안드로이드 첫 출시 준비. **코드/빌드/서명/버전 골격 완료·원격 백업됨.** 남은 건 Play Console(사용자).
> iOS 1.0.4는 별개 트랙(영향 0으로 검증). SNK 작업은 중단 상태([[SNKRDUNK_V8_STOP_HANDOFF_20260628]]).

## 0. 현재 상태 = 코드 완료
- 브랜치 **`feat/android-release`** · **원격 push 완료**(`origin/feat/android-release`, github nightfury9424/pokemon-card-app) · 미merge.
- iOS 영향 0 (모든 단계 `ios/lib/pubspec.yaml/pubspec.lock/Podfile.lock` diff 0 검증).

## 1. 식별자/프로젝트 (전부 iOS와 동일하게 맞춤)
| 항목 | 값 |
|---|---|
| Android applicationId / namespace | **`com.fury.pokemoncardapp`** (= iOS Bundle ID) |
| Firebase 프로젝트 | **`pokefolio-2e680`** (iOS/Android 공유) |
| Firebase Android 앱 | PokeFolio Android · app_id `1:794742614446:android:2c14397f0605117d17803f` |

## 2. 서명 (★iOS와 완전 별개)
- **release keystore: `~/pem/pokefolio-upload.jks`** (alias `pokefolio`, RSA2048, validity 10000d). **레포 밖·백업 필수**(잃으면 앱 업데이트 영구 불가).
- `front/android/key.properties` (storePassword/keyPassword/keyAlias=pokefolio/storeFile) — **gitignore·미커밋**. 비밀번호는 로컬에만.
- debug keystore: `~/.android/debug.keystore` (자동).
- **release SHA-1: `78:C6:8A:D5:91:C4:55:73:28:0C:68:6C:6D:40:81:45:65:B6:E0:ED`**
- **release SHA-256: `60:70:F8:F7:E0:8F:37:A0:7E:07:16:F2:6A:75:4C:92:8F:E9:3E:28:14:F4:09:0B:F4:8D:72:E3:8A:4B:68:92`** → **Firebase에 등록 완료**.

## 3. ★ 커밋 금지 (gitignore 유지)
`front/android/key.properties` · `~/pem/*.jks` · `front/android/app/google-services.json` (전부 gitignore. google-services.json은 `~/pem/google-services.json`에도 보관).

## 4. 빌드
- **최종 AAB 빌드 명령** (pubspec 안 건드리고 버전 override — iOS 빌드번호 보호):
  ```
  cd front && flutter build appbundle --release --build-name=1.0.4 --build-number=4
  ```
- **AAB 경로: `front/build/app/outputs/bundle/release/app-release.aab`** (~65MB)
- 검증: package `com.fury.pokemoncardapp` · versionName **1.0.4** · versionCode **4** · release 서명 SHA1 `78:C6:8A..` 일치(aapt2/keytool 확인).
- release 서명: **key.properties 없으면 release 빌드 명시적 실패**(GradleException) — debug 키 폴백 제거(가장 중요한 안전장치).
- R8: `front/android/app/proguard-rules.pro` 에 MLKit 미사용 다국어 인식기 `-dontwarn` 6줄.
- ⚠️ 비치명적: `failed to strip debug symbols` 경고 = cmdline-tools 누락(보류). AAB 정상·업로드 가능, 네이티브 심볼만 안 떼서 살짝 큼. 정리하려면 Android Studio SDK Manager → "Android SDK Command-line Tools" 설치.

## 5. 커밋 (feat/android-release, 소스만)
```
72592c0d chore(android): applicationId/namespace = com.fury.pokemoncardapp
9bd0d522 chore(android): Firebase google-services plugin (4.4.4)
eafc490f chore(android): release signing + R8 rules (debug 폴백 제거)
```

## 6. 남은 작업 = Play Console (사용자)
1. Play Console → Create app (포켓폴리오 · 한국어 · 앱 · 무료)
2. 위 **AAB 업로드** (internal/closed test 트랙 먼저 권장)
3. 스토어 등록정보(아이콘·스샷·설명·**개인정보처리방침 URL**·카테고리·연락처) · 데이터 안전성 · 콘텐츠 등급 · 타겟층 · 광고 여부
4. 신규 개인계정이면 **closed test 12명 × 14일** 후 프로덕션 신청
5. targetSdk 35+ 요건 — 현재 SDK36 기반이라 충족
6. ★**첫 업로드 후**: Play Console → App integrity → **App Signing key SHA-1/SHA-256** → **Firebase PokeFolio Android에 추가** (Play 재서명 키라 별도. 안 넣으면 배포판 전화인증/로그인 깨짐)
7. (나중) pubspec 버전 정렬은 **하지 말 것** — 빌드 명령 override 유지(iOS 빌드번호 보호).

## 7. 금지
merge/태그/main·dev 반영 · 추가 코드수정 · pubspec.yaml 수정 · flutter clean/pub upgrade/pod update · ios/ 수정 · 비밀파일 커밋 · SNK/naver_review 건드리기.
