# SESSION HANDOFF — 2026-06-28 (마스터)

> 다음 세션 진입점. 출시 전 3대 트랙 중 **①게시판=완료 / ②SNKRDUNK=진행중(다음 메인) / ③안드로이드=미착수**.

## 0. 큰 그림 (3 트랙)
| # | 트랙 | 상태 |
|---|---|---|
| 1 | **게시판** (조회수·알림·UI·내 활동·상세) | ✅ **완료** — 기능·UI 실기기 검증 끝. iOS 1.0.4 빌드 준비됨 |
| 2 | **SNKRDUNK 데이터** (일본 실거래 데일리 소스) | ⏳ **진행중** — 스캐너 매칭 증명·API 직접접근 확인. 파이프라인 구축 남음 ← **다음 세션 메인** |
| 3 | **안드로이드 심사 준비** | ⏳ **미착수** — 전용 세션 |

★**iOS 1.0.4(게시판 포함) App Store 심사 제출 = 아직 안 넣음, 대기(사용자 결정).** 난 제출 금지.

---

## 1. 게시판 (트랙 1 — 완료)
- **기능**: 조회수+알림(운영 Backend LIVE `myactivity-20260627`=4a2f24b9, 롤백 `rollback-pre-myactivity-20260627`=2a6ffd60) + 게시판 UI polish(텍스트형 메타·**글쓰기 연필 pill**) + 내 활동(MY 구조 재편: 커뮤니티[게시판·내활동]/준비중/고객지원 + 2탭) + 게시글 상세 레이아웃 정리(제목→본문→작성자메타→좋아요/댓글→댓글, 아바타 제거).
- **백엔드 신규 엔드포인트**: `GET /api/board/me/posts`·`/me/commented-posts` (운영 LIVE·DB 마이그 0).
- **실기기 검증 전부 PASS**: 조회수·알림·FCM푸시·딥링크·내활동2탭·상세레이아웃·연필.
- **최종 IPA**: `1.0.4 (202606280254)` (arm64·sha `0f1c1fcb`·`~/Downloads/pokefolio_1.0.4_202606280254_pencil.ipa`). 안정 RC `202606270902` 보존.
- **금칙어 검열**: 게시글·댓글·대댓글 운영 LIVE(번들 txt 4,164·fail-closed·403). 한계=공백/초성 우회·채팅 미적용(출시후 강화).
- **보존(★/tmp 정리 사고 대비)**: Front **git commit `152abdba`→`275ed94d`**(integ/board-release-1.0.4) / Backend **tar `~/Downloads/myactivity_backend_20260628.tgz`**.
- 상세: `docs/SESSION_HANDOFF_20260627.md` §0-Z.
- **남은 것 = App Store 제출 여부(사용자 결정).**

## 2. SNKRDUNK 데이터 (트랙 2 — 진행중, 다음 세션 메인)
### 최종 목표
**SNKRDUNK = 일본 실거래(sold) 가격 데일리 소스.** scrydex(참고가)와 달리 *실제 체결가*. `our_card_id ↔ snkrdunk_id` 영구 매핑 → 매일 sold pull → `SNKRDUNK_SOLD_JP`(확정만 승격·raw 적재 금지) → v8 JP-sanity-first 앵커 → **KO 시세가 추정 아니라 진짜 일본 체결가 기반**. (master flow 5단계, JP트랙은 v8 최종서만 KO와 합침)

### 이번 세션 증명/발견 (핵심)
- ✅ **스캐너 cross-source 매칭 작동**: SNKRDUNK 메가픽시 이미지 → 우리 스캐너(DINOv2+FAISS) top1 = `CRD_6657C5F9E2 메가픽시 ex SAR` score **0.793** = 텍스트매칭(m3-112) 일치 → **HIGH_CONFIDENCE**.
- ✅ **SNKRDUNK detail API 직접 curl 가능**(`curl -A Mozilla https://snkrdunk.com/v1/apparels/{id}` → JSON: id·productNumber `pkmn-tcg-M3-117`·name·image·sales). **Chrome CDP 불필요 → 내가 직접 수집 가능**(정중 rate-limit 전제).
- ✅ **텍스트 매칭** = `jp_scrydex_ref`(m3_ja-117) ↔ SNKRDUNK productNumber(pkmn-tcg-M3-117), set+번호 조인. M3 파일럿 **28/34=82%**(미매칭=카탈로그 미import).
- 스캐너 서비스 **8082 가동중**(57,160 벡터), `GET /identify_path?path=<DATA_DIR상대>` → top5(cardId·name·rarity·score), DATA_DIR=`scanner/data/`, status: ≥0.75 success / ≥0.62 low.

### 자산 위치 (다음 세션 필수)
- 파일럿 데이터: `~/Downloads/price_v8_snkrdunk/` — apparel_catalog(10, image_url은 753273만)·apparel_scan_checkpoint(131=34 POKEMON M3 set/num파싱)·recent_sales_by_apparel(94, 753273만)·match_candidates(데모 스텁).
- 수집기: `python/price_v8/snkrdunk_collect.py`(CDP방식·--selftest/--apparel/--discover, evidence CSV만)·`snkrdunk_probe.py`·`snkrdunk_match_review_gen.py`.
- 우리 카탈로그: `python/catalog_gapfill/prod_cards_full_20260620.csv`(3755행: card_id·name·collection_number·rarity_code·jp_scrydex_ref).
- 카드 이미지: `scanner/data/cards/{card_id}_jp|en|ko.png` (**3755 전부 보유**).
- 1차 인덱스 HTML(검색링크 — 부족, 보류): `snkrdunk_review_all.html` + 생성기 `python/price_v8/gen_snkrdunk_review_all.py`.
- 스캐너 테스트 이미지: `scanner/data/snktest/753273.png`. webp변환 = scanner env `/Users/fury/miniconda3/envs/scanner_v2/bin/python`(PIL 있음, base python엔 없음).

### 다음 단계 (파이프라인 구축)
1. **열거(enumeration) 조사** — 우리 카드별 SNKRDUNK id 찾는 법(set 리스팅 API / productNumber 검색 / group-items BFS). ★유일한 미지수.
2. **resolver**: API curl로 detail+image 수집(정중 rate-limit·403/429 가드·체크포인트).
3. **스캐너+텍스트 교차매칭 CLI**: SNKRDUNK img → /identify_path top5 + 텍스트(set+num) → status(HIGH_CONFIDENCE/IMAGE_ONLY/TEXT_ONLY/CONFLICT/NOT_FOUND) → `snkrdunk_scanner_match_candidates.csv`.
4. **검수 HTML**(CSV 기반): 우리img+메타 | SNKRDUNK img+title+productNumber+직접URL+sold | text/scanner 결과 | ✓/✗/? + CSV export.
5. 확정 매핑 → **매일 sold pull** → SNKRDUNK_SOLD_JP.
- **추천 진행**: M3 한 세트로 end-to-end 먼저 완성 → 같은 코드로 전 세트 확장.
- **규칙**: read-only·prod write 0·raw 가격 DB 적재 금지·확정 매핑만 승격·JP트랙 분리·정중 크롤.

## 3. 안드로이드 (트랙 3 — 미착수)
- **전용 세션 권장**. Flutter Android 빌드 설정·서명 키스토어·Play 스토어 에셋(스샷/설명)·실기기 테스트가 한 묶음.

---

## 절대 금지
App Store 제출(사용자 승인 전) · 스캐너 UI polish 재적용(원복 유지) · 조회수/알림/검열/신고/차단 로직 변경 · SNKRDUNK raw 가격 적재 · prod 직접 write(백업+승인 없이) · 오리파/경매 이름 노출·기능 구현.

## 핵심 경로/명령
- **Front 워크트리** = `/tmp/pf_board_release/front` (git worktree, branch `integ/board-release-1.0.4`, **커밋 `275ed94d`까지 보존**). ★/tmp 취약 — 변경 시 즉시 커밋.
- **Backend 소스** = `/tmp/pf_viewnotif/back` (git 아님·plain, 운영 배포본·tar 백업됨). 운영 release dir = `/opt/pokefolio/releases/myactivity-20260627`.
- IPA: `cd /tmp/pf_board_release/front && flutter build ipa --dart-define=BASE_URL=https://d33b273n14t3ne.cloudfront.net --dart-define=CARD_CDN_BASE=https://d3shjhylvfe40j.cloudfront.net/cards/v1 --build-number=$(date +%Y%m%d%H%M)` → Transporter.
- 스캐너: 서비스 8082 가동중 · `curl "http://localhost:8082/identify_path?path=snktest/753273.png"`.
- prod SSH: `ssh -i /Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120`.
- 백엔드 롤백: `docker tag pokefolio-back:rollback-pre-myactivity-20260627 pokefolio-back:latest` + force-recreate back.

---

## ▶ 다음 세션 첫 프롬프트 (복붙용)
```
docs/SESSION_HANDOFF_20260628.md 먼저 읽어.

이번 세션 목표는 SNKRDUNK 데이터 파이프라인이다.

최종 목표:
우리 3600장 카드와 SNKRDUNK trading-cards/apparels ID를 영구 매핑하고, 확정 매핑만
기준으로 매일 SNKRDUNK sold 가격을 수집해 SNKRDUNK_SOLD_JP 후보로 만든다. raw 가격 DB 직접 적재 금지.

이미 증명된 것:
- 우리 스캐너 DINOv2+FAISS가 SNKRDUNK 이미지도 인식 가능
- 메가픽시 ex SNKRDUNK 이미지 → scanner top1 = 우리 메가픽시 ex, text match와 일치
- SNKRDUNK detail API는 curl로 접근 가능
- 현재 병목은 매칭 로직이 아니라 SNKRDUNK ID 대량 열거 경로

오늘 할 것:
1. SNKRDUNK ID resolver 조사 (set listing API / productNumber 검색 / group-items / sitemap / Next.js·API JSON)
2. M3 한 세트 end-to-end 완성
   - SNKRDUNK ID 수집 → 이미지 다운로드 → scanner top5 → text match 교차검증
   - snkrdunk_scanner_match_candidates.csv 생성 → 검수 HTML 생성
3. prod DB write 0 / raw 가격 적재 금지 / 확정 매핑만 나중에 승격
```
