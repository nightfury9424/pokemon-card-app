# 공용 콘텐츠 금칙어(모더레이션) 설계안 — 2026-06-23 (조사 + 설계까지)

> 사용자 확정: 금칙어는 게시판 전용이 아니라 **모든 사용자 작성 콘텐츠 공통**. 이번 라운드는 **현황 조사 + 공용 설계까지만**.
> 채팅·거래글 실제 적용은 **별도 커밋 + 전체 회귀 테스트 + 승인 후** 진행(기존 운영 기능이므로).

## 1. 현황 조사 (read-only, 2026-06-23)

| 경로 | 금칙어 검사 | 구현 | 비고 |
|---|---|---|---|
| **게시판 글·댓글** | O | `domain/board/ContentFilter` | `banned_words.txt` + **단순 `lower.contains`** — 정규화/제로폭/우회/반복 처리 **없음** |
| **닉네임** | O | `domain/user/NicknameValidator` | NFKC+trim, banned(욕설 contains) + reserved(정확일치) + impersonation(contains). 3리스트 |
| **채팅 메시지** | ✗ | — | **누락**(grep 0) |
| **거래글 제목·본문** | ✗ | — | **누락**(grep 0) |

- **중복**: ContentFilter·NicknameValidator가 `banned/banned_words.txt`를 각자 로드(2중).
- **약점**: 둘 다 `contains` 기반. NicknameValidator만 NFKC+공백축약. `ㅅ ㅂ`/`시.발`/제로폭/반복문자 우회 미탐.
- **리스트 분리**: `banned_words.txt`(욕설=공용 후보) / `reserved_words.txt`·`impersonation_words.txt`(닉네임 전용=공용화 X).

## 2. 공용 설계: `com.fury.back.common.moderation.ContentPolicyService`

게시판·채팅·거래·댓글이 **동일 서비스 1개** 호출. 서버 저장 전 강제 검사.

### API
```
ContentPolicyService.check(String text)            // 위반 시 ResponseStatusException(403, code=CONTENT_POLICY_VIOLATION)
ContentPolicyService.violates(String text): boolean // 비throw 판정(닉네임 등 자체 메시지용)
```
- 위반 사용자 메시지: `부적절한 표현이 포함되어 있어 등록할 수 없습니다.`
- 공통 오류코드: `CONTENT_POLICY_VIOLATION`
- **위반 원문 전체를 운영 로그에 남기지 않음**(매칭 사실/카테고리/길이만).
- Flutter 검사는 **입력 보조 안내용**, 최종 방어는 서버.

### 정규화(검사 전 전처리) — 우회 방어
1. NFKC 유니코드 정규화
2. lowercase(Locale.ROOT)
3. 제로폭 문자 제거(U+200B~200D, U+FEFF 등)
4. 글자 사이 공백·일부 특수문자 제거(우회 `ㅅ ㅂ`, `시.발`)
5. 과도한 반복문자 축약(`ㅅㅂㅂㅂ`→`ㅅㅂ`)

### 목록 분리(오탐 방지)
- `banned/profanity.txt`(욕설·모욕·성적/음란·혐오/비하) — **공용**
- `moderation/allowlist.txt`(정상단어 예외) — 오탐 방지
- (선택) 불법거래/사기유도 별도 분류 파일
- 닉네임 `reserved/impersonation`은 **공용 아님**(NicknameValidator 유지). NicknameValidator는 욕설검사만 ContentPolicyService에 위임 가능(리스트 단일화).

### 적용 대상(저장 전)
채팅 메시지 / 거래글 제목·본문 / 자유글 제목·본문 / 댓글 / 1단 대댓글 / 위 콘텐츠 수정 요청.
공지글은 관리자 작성이나 길이·HTML/스크립트 검증은 유지.
**이미지 모더레이션은 별개 영역(이번 텍스트 금칙어와 분리).**

## 3. 단계적 적용(리스크 관리)
1. (이번) 조사 + 본 설계 문서.
2. `ContentPolicyService` 신규 + 단위 테스트(아래) — 기존 경로 미접촉.
3. **게시판**(BoardWriteService) ContentFilter → ContentPolicyService 교체(정규화 강화).
4. **채팅·거래글** 적용 = ★별도 커밋 + 전체 회귀 + 승인(기존 운영 기능).
5. NicknameValidator 욕설검사 위임(리스트 단일화) — 선택.

## 4. 필수 테스트
- 정확한 금칙어 / 띄어쓰기 우회 / 점·특수문자 우회 / 제로폭 우회 / 반복문자 우회 / 정상단어 오탐 방지(allowlist)
- 적용 경로별 create·update: 채팅·거래글·자유글·댓글·대댓글
- 회귀: 기존 정상 메시지·거래글·게시글 통과

## 5. 금지(이번 라운드)
ContentPolicyService 구현·채팅/거래 적용·prod·dev통합·IPA·push 모두 **다음(승인 후)**. 이번엔 조사+설계 문서까지.
