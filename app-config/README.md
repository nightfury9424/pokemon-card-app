# app-config (S3 정적 설정)

앱이 백엔드와 **독립**으로 읽는 정적 JSON. S3 버킷 `pokefolio-beta-assets-…-an` 의
`app-config/` 키, **public read**(버킷 정책에 `maintenance.json` + `version.json` 화이트리스트).
앱은 `cardCdnBase` 호스트의 `/app-config/{file}` 를 30s 캐시버스트로 폴링. fetch 실패 = **fail-open**.

## maintenance.json — 점검 모드
관리자 웹 "점검 시작/종료" 버튼이 재업로드. `{"maintenance": bool, "message": str}`.

## version.json — 업데이트 게이트
```json
{ "autoForceUpdate": true, "minBuild": 0, "latestBuild": 0, "iosStoreUrl": "https://apps.apple.com/app/id6772926395", "message": "" }
```

### ① AUTO 강제 (기본 동작 — version.json 없이도 ON)
앱이 **App Store(`itunes.apple.com/lookup`)에서 현재 최신 마케팅버전을 직접 조회** → 설치버전이 더 낮으면 **자동 강제 업데이트**. 새 버전 출시만 하면 구버전 사용자에게 자동 적용(수동 설정 0). 강제 대상이 스토어에 실재 → brick 구조상 불가. **심사 안전**(심사 빌드는 항상 스토어 최신보다 새 버전 → 미발동).
- **`autoForceUpdate: false` = ★킬스위치** — 재빌드 없이 AUTO 강제 OFF. (필드 없음/파일 없음/fetch 실패 = 기본 ON)

### ⚠️⚠️ 단계적 출시(Phased Release) 금지 — 또는 출시 중 킬스위치 (Codex P1)
**App Store '단계적 출시'를 쓰면 안 됨.** lookup은 1%만 받아도 새 버전을 즉시 반환하는데, 나머지 99%는 아직 못 받아서 → **강제벽에 갇힘(업데이트 눌러도 못 받음)**. 반드시:
- **100% 즉시 출시**(단계적 출시 OFF)로 릴리즈, **또는**
- 단계적 출시를 쓸 거면 **출시 전 `autoForceUpdate:false`로 꺼두고, 100% 도달 후 다시 true**.
- 참고: lookup CDN 전파 ~5~30분 지연 → 출시 직후 강제 발동까지 약간 텀(정상).

### ② 수동 override (선택 — 특정 빌드 강제/권장)
- `minBuild` **미만** 빌드 → HARD, `latestBuild` **미만** → SOFT(닫기 가능·latestBuild당 1회). 빌드번호=`CFBundleVersion` `YYYYMMDDHHMM`.
- 가드: 미래값(현재 UTC+1일 초과)인 항목은 무시(독립 적용), `minBuild>latestBuild`면 minBuild HARD skip(self-lock).
- ★철칙: 값에 **실제 출시된 빌드번호 초과 금지**(전원 강제 잠김). 대상 빌드 실제 번호 그대로 복사.

### 업로드 방법 (Claude가 boto3로 1커맨드 — `[[project-update-gate-ops]]`)
miniconda boto3 + `~/.aws` default(계정 759135635310) → `put_object(app-config/version.json, ContentType=application/json)`. 또는 AWS 콘솔 수동 업로드(버킷정책 public read 자동). 검증=curl 200.
