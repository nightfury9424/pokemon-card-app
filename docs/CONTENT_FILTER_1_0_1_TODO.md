# Content Filter (UGC 금칙어) — 1.0.1 TODO

## 배경
App Review **Guideline 1.2 #2** = "a method for filtering objectionable content".

- **현재 prod 상태**: 금칙어 필터는 **닉네임 전용**(`NicknameValidator` + `banned/banned_words.txt`) + 반응형 모더레이션(신고→24h 삭제 + 차단). → 1.2 #2 최소 충족.
- **2026-06-10 시도→revert**: 채팅/거래글/메모에 `ContentFilter`(substring `contains` + mask) 확장 구현했으나 **오탐 심각**으로 배포 전 전량 revert.
  - `Master Ball`/`마스터볼` → `master` 매칭 → 거래글 거부 (포켓몬 앱 치명)
  - `classic` → `ass`, `확인해보지 못했습니다` → `보지`
  - 추가 결함: `updateTrade`(PUT) 우회, NFKC 미정규화(전각 우회), 메시지당 4,160개 스캔(성능).
  - 근본 원인: `banned_words.txt`가 **닉네임용 범용 리스트**(비욕설어·짧은 부분문자열 포함) + substring 매칭.

## 1.0.1 구현 요구사항
1. **Curated 키워드 리스트 (닉네임 리스트와 분리, 신규 작성)**
   - 욕설/비속어 (오탐 안전한 것만)
   - 불법거래 (마약·계좌매매·현금화·대리구매 사기 등)
   - 개인정보 요구 (주민번호·계좌번호·카드번호·외부 송금 강요 등)
   - ★카드명/세트명/일반어 배제 — "마스터볼/Master Ball/classic" 등 통과
2. **Unicode NFKC 정규화** 후 매칭 (전각 `ａｄｕｌｔ`·호환문자·제로폭 문자 우회 차단)
3. **token/boundary 기반 매칭** (substring `contains` 금지). 한글은 경계/형태소 고려 (`보지` vs `해보지`)
4. **적용 범위 전체**: chat `sendMessage` / trade **create**(description) / trade **update**(`updateTrade` PUT — 우회 차단) / buy order create+update(memo)
5. **정책**: 채팅 = 마스킹(`***`, 메시지 유실 X) / 거래글·메모 = **등록 거부 + 사유 안내**("부적절한 표현이 포함되어 있어요. …수정 후 다시 등록")
6. **False-positive 회귀 테스트 (must-pass)**: `Master Ball`, `마스터볼`, `classic`, `확인해보지 못했습니다`, 주요 카드명/세트명 정상 통과
7. **관리자 override + logging**: 필터 히트 로깅(어드민 검토용) + 오탐 화이트리스트 + 어드민 강제 통과
8. **성능**: length cap + Aho-Corasick(또는 curated 소형 리스트)로 메시지당 전수 스캔 회피

## 후보 리스트/라이브러리 (2026-06-10 리서치)
메타 저장소: **github.com/Tanat05/korean-profanity-resources** (datasets/libraries/APIs 25+ 정리).

★**라이선스 필수: MIT/Apache만 (상용 가능).** hate-speech 대용량 데이터셋(kmhas, korean_unsmile 등)은 **CC BY-NC = 상용 불가 → 제외.**

| 후보 | 형태 | 라이선스 | 적합성 |
|---|---|---|---|
| **BadWordFiltering** (Java) | JVM 네이티브 라이브러리 | MIT | Spring 직접 연동 최적. 매칭방식(경계/변형) 검증 필요 |
| **korcen** (korcen-go / korcen-api REST / korcen.ts) | 키워드 + 변형·우회 처리 | Apache 2.0 | `ㅅㅂ`/`시1발`/전각 우회 강함. grading·scanner처럼 **REST 사이드카**로 운용 가능 |
| f-word (Python) | 리스트/필터 | MIT | 참고 |
| slang.csv (4,315) | CSV 워드리스트 | (확인 필요) | 현 리스트와 유사규모 → 큐레이션 없이 쓰면 동일 오탐 |

권장: **korcen(변형/우회) REST 사이드카** 또는 **BadWordFiltering(JVM, MIT) 직접 연동** + 우리 **도메인 화이트리스트**(Master Ball/마스터볼/카드명·세트명). 둘 다 NFKC + 경계매칭 + 오탐 회귀테스트 통과 전제.

출처: `Tanat05/korean-profanity-resources`, `Tanat05/korcen`, `BadWordFiltering`(JVM), 현 사용 중·교체대상 `doublems/korean-bad-words`+`hlog2e/bad_word_list`.

## 참고
- revert된 구현 시작점: `ContentFilter.java`(substring+mask) — git 히스토리. 매칭 전략·리스트는 위 요구사항대로 재설계.
- 닉네임 필터(`NicknameValidator`)는 그대로 유지(별개 목적). 단 닉네임도 동일 오탐 가능성은 별도 검토.
