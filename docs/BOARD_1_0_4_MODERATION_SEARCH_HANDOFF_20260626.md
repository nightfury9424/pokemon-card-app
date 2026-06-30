# 게시판 1.0.4 모더레이션 + 검색/공지 핸드오프 (2026-06-26)

> **상태: 전부 구현·로컬테스트 완료 / 운영 미배포.** 운영 Backend 이미지=`7ee334d7`(이번 변경 미포함),
> DB migration 미적용, Admin dist 미배포, 새 IPA 미생성. 배포는 #9 게이트 통과 후.
> 코드 소스 단일원: `/tmp/pf_board_release` (HEAD `8cb27191`, working tree clean). 백엔드 배포본=`/tmp/pf_prod_baseline` working(SHA 일치).

이 문서는 런타임 코드가 아니라 **현재 구현 상태의 단일 진실원**이다. (문서만 — 코드 무변경)

---

## 1. 신고·차단 정책 매트릭스 (단일 판정원 = `BoardPermissions.canBlock{Post,Comment}Author`)

차단 가능 판정은 `isAdmin` 기준 **하나의 헬퍼**로 일원화(placeholder/override 제거). DTO 권한·신고 자동차단·수동차단·UI 전부 동일 판정 사용.

| 대상 | 신고(report) | 차단(block) | 비고 |
|---|---|---|---|
| 공식글(notice/event/patch) | 가능 | **불가** | 글 타입이 공식 → 운영팀 |
| 운영팀 작성자의 자유글 | 가능 | **불가** | 작성자 allowlist(isAdmin) → 자유글이어도 차단금지 |
| 운영팀 댓글(commentIsAdmin OR allowlist) | 가능 | **불가** | |
| 일반유저 자유글/댓글 | 가능 | 가능 | 기존 동작 보존 |
| 공식글의 **일반유저 댓글** | 가능 | **가능** | 부모글 타입 아닌 댓글 작성자 기준 |
| USER/TRADE/CHAT | 가능 | 가능(per-user) | 기존 정책 불변 |

- 신고 시 자동차단: `autoBlock = canBlock*Author(...)` — 운영팀 대상이면 신고 row만 생성, **block row 0**.
- `ReportService.create`의 6-arg 오버로드 제거 → 모든 호출부 `autoBlock` 명시(기본 true 우회 차단).
- 검증: BoardPermissionsTest 16/0, BoardServiceTest 17, BoardBlockTest 13, ReportService/Controller. 커밋 `ec8c68db`·`05905978`.

## 2. OTHER 신고 상세사유 필수
- Backend: `OTHER` + detail 공백 → 400(`ReportController`). Front: 빈칸 제출 버튼 비활성 + 사유 변경 시 detail 초기화(`report_sheet`).
- 커밋 `05905978`(BE)·`d916caa7`(FE).

## 3. 게시판 신고 중복 정책 (per-target / per-user 분리)
- **BOARD_POST/COMMENT** = `reporter_id + target_type + target_id` 단위(글/댓글별). 같은 작성자의 다른 글·댓글은 각각 신고 가능, 같은 글/댓글 재신고만 400.
- **USER/TRADE/CHAT** = 기존 `reporter_id + target_user_id`(per-user) 보존. BUY_ORDER = PENDING per-target 보존.
- DB: `uq_reports_reporter_target`(partial unique **INDEX**, constraint 아님)를 비게시판 전용으로 교체 + 신규 `uq_reports_reporter_board_target`(게시판 per-target). `back/sql/reports_dedup_migration.sql`(+rollback). **DROP INDEX 사용**.
- dry-run BEGIN→검증→ROLLBACK 성공, 충돌 0. ReportControllerTest 15/0. ★실제 DB 통합테스트=#14(Docker). 커밋 `853b5211`·`f95dce1a`.
- ★코드+index는 **한 배포 단위**로 같이 적용(분리 시 앱검사↔DB방어 어긋남).

## 4. 운영팀 공지 댓글·대댓글 (Admin 웹에서 직접 작성)
- Backend: `POST /api/admin/board/posts/{postId}/comments`(admin-gated) → `BoardWriteService.createAdminComment` = **admin=true** 저장.
  - **공식글(notice/event/patch)에만** 허용(`asAdmin && !isAdminType` → 403). 공식글의 일반유저 댓글에 운영팀 대댓글 허용.
  - 운영팀 댓글도 **콘텐츠 정책(금칙어) 동일 적용**(면제 아님 — admin=true 표시·차단불가와 별개).
  - 읽기는 admin_token이 통하는 기존 `GET /api/board/posts/{id}`(스레드 댓글 포함) 재사용.
- Admin 웹: 공지 행 **[댓글]** → 상세 모달(본문+댓글 스레드+작성/답글, textarea, 운영팀 작성, 댓글수 갱신).
- 앱: 변경 0 — 운영팀 댓글은 단일화로 이미 운영팀 배지+신고가능/차단불가 렌더.
- BoardWriteServiceTest 37/0, admin build OK, admin_token 상세 GET 200 실측. 커밋 `2d380261`·`d8823bc2`. ★배포 후 live POST·앱연동 실검(#13 잔여).

## 5. Admin 공지 작성·수정 앱 미리보기
- Notices 모달 우측 폰 미리보기(목록/상세 토글·live): 타입배지 lucide 아이콘(type.color, 앱 Icon+label 구조)·제목·내용·**파란 '고정' 배지(이모지 없음)**·운영팀 표시. preview only(저장 독립). 기존 등록/수정/삭제/단일고정 무변경.
- admin build EXIT=0. (#12)

## 6. 카드 검색에 세트명 포함
- `/api/cards/search`(사용자 직접 검색: asset·trade_search·grading)만 수정 → `searchByCardNameOrProductName[AndLanguage]` = 카드명 OR 세트명. `/market`·rarity browse·미사용 메서드 비접촉.
- 세트명은 **「」 안 고유명 우선**(없으면 전체명 fallback)으로 매칭 → 'MEGA/확장팩/소드' boilerplate 폭발 차단(확장팩 2494→59).
- prod 실측: 어비스아이 0→39, 어비스→어비스아이+로스트어비스 75, 카드명(다크라이/리자몽) 유지, 중복 0. 정렬 미지정(기존 보존).
- 커밋 `63d413b5`·`5ede8b72`. ★PG Repository→Service→API 통합테스트=#15(Docker). `/cards/search`는 limit/min-length 없음 — 광범위어 응답량은 #15에서 측정.

## 7. 게시판 목록 카운터
- 순서 **좋아요→댓글→조회**, 값 0 포함 **항상 표시**(좋아요 `if(>0)` 조건부 제거). `_meta` Row 세로중앙 + Wrap center. 공지/이벤트/패치/자유 + 검색결과(동일 itemBuilder) 전부 동일.
- 집계·좋아요 클릭(상세 토글)·조회증가 로직 무변경. 모델 int 기본0(null 안전). 커밋 `cff9dc8e`, board_list_layout+#6·board_like 31 PASS.

## 8. 게시판 검색창 상태 보존
- 검색 TextField 1줄(`maxLines:1` + `textAlignVertical.center`) → 입력·힌트·X 수직중앙(2줄처럼 보이는 현상 제거), 320px overflow 0.
- 상세 진입 직전 `FocusScope.unfocus()` → 키보드 닫힘. 복귀 시 검색모드/검색어/결과 유지, 키보드 자동 재오픈 안 함(검색창 재탭 시만).
- ★`_silentReload`가 `q` 누락하던 버그 수정(검색 중 복귀 시 전체목록 복원 방지 → 검색결과 보존). 커밋 `8cb27191`, board 회귀 PASS.

## 9. 게시판 상세 좋아요 race (기존 동작 — 변경 없음)
- 낙관적 토글 + 실패 시 롤백 + 요청 중 뒤로가기 차단(완료/롤백 후 결과 반영). board_like_test 31 PASS로 고정. 이번 세션 미변경(회귀 가드).

## 10. 홈 배너 + 탭 정책 (기존 — 변경 없음)
- 홈 공지 배너 = **고정된 공식글 1개만**(`GET /api/board/posts?section=official&pinnedOnly=true&size=1`). 고정 0건/로딩/오류 = 배너 숨김. 관리자 고정 해제 시 즉시 사라짐.
- 게시판 탭 = `BoardFilter {all, notice, free}` = 전체/공지/자유 2탭+전체. 좌측정렬·전체폭(가운데 모임 방지). 이번 세션 미변경.

---

## 커밋 맵
`73fce33a`(이전 FE: 스와이프뒤로/pull-refresh/라벨) · `05905978`(P0 autoblock+OTHER) · `ec8c68db`(단일화+6arg제거) · `d916caa7`(OTHER FE) · `853b5211`+`f95dce1a`(#10 신고중복) · `2d380261`+`d8823bc2`(#13 운영팀댓글) · `63d413b5`+`5ede8b72`(#5 세트검색) · `cff9dc8e`(#6 카운터) · `8cb27191`(#7 검색창)

## 배포 delta (미실행 — #9에서 확정)
운영 `7ee334d7` 대비 path-scoped delta만 배포. working 60파일 통째 빌드 금지.
- **배포 대상**: report(Controller/Service/Repository)·block(Controller)·board(Permissions/Service/WriteService/AdminController)·card(Repository/ServiceImpl)·`back/sql/reports_dedup_*`·admin/Notices.jsx·Reports.jsx
- **이미 운영 반영**: asset/dex/DexService·storage/ImageProxyController + board read/write/admin 베이스
- **순서**: ①DB migration + Backend 코드(한 단위) ②healthy+스모크 ③Admin path-scoped dist ④Admin 스모크 ⑤nightfury 잘못된 block row만 복구 ⑥앱 실기기 ⑦새 IPA
- **배포 전 필수 백업**: 현 이미지/tag, Admin dist, reports DDL/index/data dump, nightfury block row, migration rollback SQL, 이미지/dist rollback 절차.
