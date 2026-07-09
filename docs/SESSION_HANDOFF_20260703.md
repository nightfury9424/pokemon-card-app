# SESSION HANDOFF — 2026-07-03

> 다음 세션 진입점. 두 갈래: **①SNKRDUNK 후쿠오카 프로모 파일럿(진행중)** + **②새 IPA 빌드 + TestFlight 체크리스트**.

---

## ★★★★같은 날 밤 — 브랜치 대청소 완료 + 1.0.6 심사 제출됨 (진짜 최종 상태)

**브랜치 최종 구조 (로컬=원격 동일, 딱 2개)**:
- **`main`** = 유일 트렁크(122d6096). 메인 폴더도 main 체크아웃 상태. **모든 릴리즈(iOS/Android/백엔드)는 여기서만 컷.**
- **`capture/prod-20260703`** = prod 서버 소스 동기화 레인(서버가 이 브랜치에 커밋된 채 상주 → 서버 hotfix 시 서버에서 커밋 → Mac fetch → main 반영).
- 삭제된 34개 브랜치 전부 **`arch/<이름>-20260703` 태그로 보존**(유실 0). 대형 로컬 스냅샷 2개(arch/backup-pre-push-binary-history·arch/wip-full-snapshot-20260518)는 로컬 태그 전용(원격 push 금지 — 바이너리 폭탄).
- 워크트리 4개 제거(pokefolio_106/ios105/unified/app-sync — 전부 클린 확인 후). 메인폴더 dirty였던 tracked 4파일은 `arch/mainfolder-dirty-20260703` 태그로 보존.

**iOS 1.0.6 = 심사 제출 완료(07-03 19:47·빌드 202607031031·심사 대기 중)**. 승인 후: ①전체 즉시 출시(phased 금지) ②version.json 게이트 활성화(minBuild=202607031031 → 1.0.4 이하 강제·1.0.5는 사각지대→고정공지로 유도) ③고정공지 1.0.6 갱신.

**다음 Android 빌드(갤럭시탭 테스트용)**: main에서 `flutter build appbundle --release --build-name=1.0.6 --build-number=<vc5+>` — main에 android 설정(com.fury.pokemoncardapp·서명·R8·google-services) 포함 확인됨. keystore `~/pem/pokefolio-upload.jks`.

## ★★★같은 날 저녁 — main 단일트렁크 승격 완료 (최종 상태)

- **main = `122d6096`** (fast-forward·히스토리 손실 0·push 완료) = 1.0.6 front(스캐너 2모드+썸네일픽스+드리프트복구+android 설정) + **back/src/main=prod 캡처와 바이트 동일**(board 복구+JP시장 패밀리+NAVER fix) + board 마이그SQL/테스트 + SNK 파이프라인 도구 최초 커밋.
- **prod 서버 소스 = git 추적 시작**: 서버 `/opt/pokefolio/app`이 `capture/prod-20260703`(`76a98781`) 브랜치에 커밋된 상태로 상주 — "서버에만 있는 코드" 0. 동일 커밋이 GitHub에도 push됨. **앞으로 서버 hotfix는 이 브랜치에 커밋 후 Mac에서 fetch.**
- 백업: `bak/main-pre-trunk-20260703`(구 main)·태그 `v1.0.6`(5fb33c30=IPA 202607031031 빌드 커밋)·`trunk-20260703`. 전부 원격 push됨.
- 검증: trunk back/src/main==capture diff 0(컴파일 보장)·flutter analyze error 0·배치2(토호쿠/히로시마) 폰 PASS·게시판 E2E 13/13.
- **남은 것**: ①1.0.6 심사 제출(사용자 버튼 — version.json dormant 확인됨 minBuild=0/latestBuild=0) ②Android closed testing 심사 대기→갤럭시탭 opt-in 14일 ③내일 아침 NAVER 오염 0 확인 ④레거시 브랜치 정리(선택: dev/integ류 — 급하지 않음).

---

## ★2026-07-03 오전 UPDATE — 표시 fix [A] prod 배포 완료 (폰 검증만 남음)

- **fix [A] 배포 LIVE**: JP 시장 패밀리(`source IN ('SCRYDEX_JP','SNKRDUNK')`) 신규 쿼리 4개(`PriceSnapshotRepository`: findLatestJpMarketByCardIds/findLatestJpMarketPsa10ByCardIds/findJpMarketHistory/findJpMarketPsaHistory — **기존 메서드 무접촉·추가만**) + `getCardPriceSummary` JP 사이트 6곳 교체(jpSnapsHistory·jpRawSnap·jpPsa10Snap·jpPsa10/9Line·repJp). **KO_ESTIMATED 폴백 2블록은 .bak_pre_snkfix 기준 정확히 되돌림**(net diff에 흔적 0). **카드 하드코딩 0 — SNKRDUNK 행 있는 카드면 자동 적용**(토우호쿠/히로시마 확장 시 데이터만 넣으면 됨, 백엔드 재배포 불필요).
- **검증 실측**: 회귀 3장(요코하마 WCS `CRD_CF5D258E4C4326F86707666D9357D5A2`·메타몽 프로모 `CRD_205C20056CBF48F8B08D`(promoexcl=**false**·KREAM 경로)·일반JP) API 응답 **before/after 바이트 동일**. 후쿠오카 API: `charts.jp` line=14/psa10=15/psa9=9, jpPsa=$293.63/$94.23, ko.mid=152,480, label=OVERSEAS_REF, representativeKrw.jp=152,480.
- **카드 노출됨**: `is_visible=TRUE` (2026-07-03 오전).
- **롤백**: 이미지 `pokefolio-back:bak-snk-koest-20260703`(=KO_ESTIMATED 폴백판 b57f1f1c) / `rollback-pre-snkfix-20260703`(fe213d19, pre-snkfix) + 소스 `.bak_snk_koest_20260703`·`.bak_pre_snkfixA_20260703`·`.bak_pre_snkfix_20260703` + 재숨김 UPDATE 한 줄. 현 running=d5ffb674.
- **회귀 비교 방법 기록**: prod API 인증은 JWT_SECRET(.env.prod)으로 HS256 토큰 직접 발급(→ /tmp/snkfix_token.txt 사용 후 삭제됨). 엔드포인트 = `/api/prices/cards/{cardId}/price-summary`.
- **리스트 경로 후속 fix(같은 날 오전 2차 배포)**: 폰 검증서 상세는 정상인데 **리스트 "시세 없음"** 발견 — 리스트/검색은 별도 경로(`CardServiceImpl` getCardWithPrice + buildNativeResult)가 SCRYDEX_JP만 봄. fix = `findLatestMarketSnapshotsByCardIds`에 'SNKRDUNK' 추가 + JP 슬롯 폴백 2곳 + PSA10 폴백→`findLatestJpMarketPsa10ByCardIds`(4곳, 하드코딩 0). 검증: 후쿠오카 리스트 `koEstimatedPrice=152480/RAW/OVERSEAS_REF`, 회귀(요코하마PR·메타몽 리스트) **필드 단위 0 diffs**(바이트 차이는 JSON 키 순서뿐). 백업 `.bak_pre_snklist_20260703` 2파일 + 이미지 태그 `bak-snkfixA-20260703`(=1차 fix판).
- **남은 것**: 폰 검증(검색 리스트 시세 표시 포함: JP 탭·RAW/PSA10/PSA9 3등급·"해외 참고가" 라벨·이미지 타이트·스캔 인식·자산 등록). 이상 시 위 롤백.

## ★★같은 날 오후 2 — 게시판 증발 사고 복구 (필독: memory/project_board_missing_source_incident_20260703.md)
- 증상: 1.0.5/1.0.6 게시판 "No static resource /api/board/posts". 근본=**서버 트리에 board 소스 부재**(6월 배포는 /tmp 워크트리 빌드) → 7/1 16:17 linkUrl 풀리빌드부터 board 없는 이미지. 복구=①June 이미지 클래스 diff(51개 특정) ②unified서 board+moderation+지원류 반입·block/report 교체 ③알림 3클래스+notification 병합(`~/Downloads/board_view_notify_deploy_20260627.tgz`서 발굴). **최종: June 패리티 256/256·시세 무손실·LIVE**. 교훈=**prod 리빌드 전 class-diff 게이트**. 남은=폰 검증(게시판·댓글알림·좋아요알림·딥링크).

## ★같은 날 오후 — 배치 2(토호쿠+히로시마) prod LIVE + NAVER 매처 fix
- **토호쿠의 피카츄 `CRD_7D01660BE6EE463A9147`**(SVP000000260·aid 618445) + **히로시마의 피카츄 `CRD_83FC369C80BE4028B722`**(SVP000000261·aid 618446) — 검수HTML 승인→importer(`product_id` 공유지정+`--hidden` 신설)→백업 `~/pokefolio_backups/snk_batch2_20260703/`→apply→이미지(알파 bbox 크롭+흰배경, special/ 200)→backfill(134/140/100·182/216/115일)→벡터 prod pull 베이스 체인 +20→**reload-index {ok,57130,3892}**→visible=true→API 검증 전부 정상(상세 JP 3등급·리스트 ₩143,400/₩145,790·OVERSEAS_REF). 로컬 scanner/db=57130 동기화. **남은=폰 검증**(검색·상세·스캔 인식·이미지).
- **NAVER 매처 fix 배포**: `price_naver_cafe.py` 매칭 3쿼리에 `is_promo_exclusive=FALSE` 제외(오염은 숨김카드에도 붙었음). 롤백 `bak-pre-naverfix-20260703`. 오늘 22시 크론부터 유효 — 내일 아침 3장 오염 0 확인.
- 배치 3 후보(scrydex 존재 확인 후 레인 결정): Nagaba 피카츄 S-P208·피카츄VMAX S-P265·우표BOX S-P227·Nagaba 이브이즈 SV-P062-070·(검수518 內)SV-P001 피카츄(수요 전체 2위).
- 참고: ko.basis 문자열이 "SCRYDEX_JP_DIRECT"로 나오는 건 프로모 분기 legacy 내부 라벨(UI 라벨은 OVERSEAS_REF로 별도) — cosmetic, 추후 소스명 파생으로 정리 후보.

---

## ① SNKRDUNK 일본 독점 프로모 파일럿 — 후쿠오카 피카츄 (진행중·표시 fix 남음)

### 현재 prod 상태 (2026-07-03 정리 후)
- 카드 **`CRD_935FD6C6A2554FA7AD2A`** = **is_visible=FALSE (숨김, 앱 미노출)**
  - official_card_code `SVP000000289` · product `JP_PROMO_EXCLUSIVE`(판쵸 등 공유·"일본 독점 프로모") · is_promo_exclusive=TRUE · jp/en=NO_JP/NO_EN · rarity PR
  - SNKRDUNK 매핑: `card_external_refs` source='SNKRDUNK' external_id='618447' is_active=TRUE
- 시세 데이터: `price_snapshots` **source='SNKRDUNK'** 40행(RAW 15 / PSA10 16 / PSA9 9) + KO_ESTIMATED 15. **정직한 라벨로 복원됨**(SCRYDEX_JP 마이그는 되돌림).
- **daily cron 정상 작동 검증됨**: `58 23 * * * /opt/pokefolio/cron/price_snkrdunk_promo_daily.sh` — 매일 SNKRDUNK sales-history RAW(A)/PSA10/PSA9 3등급 → JPY→KRW(9.53, ÷100) → append-only 축적. 07-02/07-03 실측 정상, 100배 없음.
- 이미지: 사용자 Photoroom 누끼 → 카드 bbox 타이트크롭 **`fukuoka_tight.png`(435×608, 여백0)** = 스크래치패드. S3 `cards/v1/special/{cid}.png`에 업로드돼 있음(HTTP 200).
- 벡터: prod scanner에 10개(augment10) 있음 → **ntotal 57110**. ★근데 카드가 숨김이라, 스캔 매칭돼도 카드로드 실패 가능(@SQLRestriction). 노출 시 정상. 백업 `.bak_pre_snk2_20260703`(57100).
- 백엔드: 내가 배포한 **KO_ESTIMATED 폴백 fix는 방향이 틀림(메타몽식 KO탭·RAW만)** → 아래 참조.

### ★★핵심 학습 — 표시 fix (다음 세션 최우선)
**증상**: 후쿠오카가 앱에서 **KO 탭 · RAW만** 뜸(메타몽 짝퉁). **정답 = 요코하마 피카츄(283/SM-P)처럼 JP 탭 · RAW/PSA10/PSA9 3등급.**

**왜**: 요코하마는 `jp_scrydex_ref`(scrydex에 있음) → SCRYDEX_JP 스냅샷 → 프론트가 JP 차트로 표시. 후쿠오카는 scrydex 없음(svp_ja-289=404) → 데이터가 source='SNKRDUNK' → 기존 프레임워크가 **SCRYDEX_JP만 읽어서** JP 차트 비어있음 → 폴백 KO.

**프론트 로직**(`front/lib/features/card/card_detail_screen.dart:3010 _availableMarkets`):
```
OVERSEAS_REF(is_promo_exclusive)면 KO 제외 + _hasAnyChartData(charts['jp'])면 JP추가 + 비면 KO폴백
→ _selectedMarket = latest.first
```
즉 **JP 탭은 jp_scrydex_ref 아니라 `charts.jp`에 데이터 있으면 뜬다.** charts.jp는 백엔드 JP 차트(jpLine/jpPsa10Line/jpPsa9Line)에서 옴 = source='SCRYDEX_JP' 읽음.

**백엔드 JP 차트 소스**(`GlobalPriceService.getCardPriceSummary`, ~L2103):
- `jpSnapsHistory` = findByCardIdAndSource(cardId, **"SCRYDEX_JP"**, cutoff)
- `jpPsa10Line/jpPsa9Line` = findScrydexPsaHistory(cardId, **"SCRYDEX_JP"**, "10"/"9", cutoff)
- `jpRawSnap` = findLatestScrydexJpByCardIds / `jpPsa10Snap` = findLatestScrydexJpPsa10
- promoExclusive 분기(L1932): formulaPrice = jpRawSnap→jpPsa10Snap→enRawSnap

**두 가지 fix 옵션**:
- **[A · 권장·정직]** JP 차트 관련 쿼리 5곳을 `source IN ('SCRYDEX_JP','SNKRDUNK')`로 확장 → 데이터는 SNKRDUNK 라벨 유지, 프레임워크가 읽음. + 내 KO_ESTIMATED 폴백 코드 **되돌리기**(dead·틀림). 백엔드 재빌드+배포.
- **[B · 데이터 hack]** SNKRDUNK 스냅샷을 source='SCRYDEX_JP'로 UPDATE → 코드 0. **단 라벨이 거짓말(사용자 반대) + 캐시 무효화 필요.** 비권장.

**★캐시 주의**: `@Cacheable("cardPriceSummary", key=cardId)` — **Caffeine 30분 TTL**(`CacheConfig.java`). 데이터/코드 바꿔도 **30분간 옛 응답 서빙**. fix 후 30분 대기 or 백엔드 재시작으로 즉시 반영.

**통화**: JP 탭 타일은 `psa10Usd`(USD 등가·snapsToPoints가 KRW/exchangeRate). SNKRDUNK는 raw_currency='JPY' → toLatestKrw가 jpyToKrw로 변환 → $ 등가 표시(요코하마 $처럼). 정상.

**라벨**: is_promo_exclusive → OVERSEAS_REF → "해외 참고가"(price_label.dart) 자동. 유지.

### 되돌림/롤백 참조
- 백엔드 이미지: 현재 running=852dc3e(내 KO_ESTIMATED fix 포함). 롤백태그 `pokefolio-back:rollback-pre-snkfix-20260703`(fe213d19). 소스백업 `.bak_pre_snkfix_20260703`.
- scanner: `.bak_pre_snk2_20260703`(57100) → cp+restart로 복원.
- DB: `~/pokefolio_backups/snk_fukuoka_20260702/ROLLBACK.md`(cards_products 덤프 + targeted DELETE). card_id=CRD_935FD6C6A2554FA7AD2A.

### 파이프라인 파일 (`python/price_v8/`)
`snkrdunk_promo_schema.sql`(card_external_refs) · `import_snkrdunk_promo_cards.py`(등록·중복검사) · `snkrdunk_import_list.csv` · `sync_snkrdunk_promo_prices.py`(daily 3등급 append) · `backfill_snkrdunk_promo_prices.py` · `gen_snkrdunk_promo_review.py`(검수HTML) · `scanner/add_catalog_card_vector.py`(augment10 10벡터). prod cron 스크립트=`/opt/pokefolio/scripts/sync_snkrdunk_promo_prices.py`+config.py, 래퍼 `/opt/pokefolio/cron/price_snkrdunk_promo_daily.sh`.

### 다음 세션 순서 (후쿠오카 마무리)
1. **백엔드 fix [A]**: JP 차트 쿼리 SNKRDUNK 읽게 + KO_ESTIMATED 폴백 되돌림 → 로컬 검증 → 배포(롤백태그 잡고).
2. **캐시**: 배포=재시작이라 자동 클리어. or 30분 대기.
3. is_visible=true.
4. 폰 검증: **JP 탭 · RAW/PSA10/PSA9 3등급 · 이미지 타이트 · 스캔** = 요코하마처럼.
5. 성공하면 daily/backfill 스크립트 그대로(SNKRDUNK), 토우호쿠(260)/히로시마(261) 확장.

### 접속/운영
`ssh -i ~/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120` → `docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db`(★한글 stdin파이프·다중SELECT는 단일+서브쿼리). 백엔드 빌드=`cd /opt/pokefolio/app && docker build -f back/Dockerfile -t pokefolio-back:latest .` → `docker compose --env-file /opt/pokefolio/.env.prod -f docker-compose.prod.yml up -d --force-recreate back`(★service명 `back`). scanner 스왑=staging S3업로드→presigned(★리전엔드포인트 s3.ap-northeast-2 + SigV4, 기본은 307)→back컨테이너서 `/admin/reload-index` POST(토큰 UNSET).

---

## ② 새 IPA 빌드 + TestFlight 검증 체크리스트

새 IPA 빌드해서 TestFlight 올리고 아래 검증 (E는 현 빌드 픽스 미포함 표시).

**A. 스캐너 — 자동 모드**
- [ ] 1. 스캔 진입 시 자동 모드 기본 진입 (셔터 없이 실시간 스캔)
- [ ] 2. 하단바 우측 원형 모드전환 버튼 + 상단 중앙 "자동" 상태글자
- [ ] 3. 카드를 프레임에 맞추면 자동 인식 → 결과 시트
- [ ] 4. "카드를 프레임 안에 맞춰주세요" / 인식 중 인디케이터 정상

**B. 스캐너 — 촬영 모드**
- [ ] 5. 우측 버튼 → 촬영 모드 전환 → 중앙 흰 셔터 등장, 상단 "촬영"
- [ ] 6. 셔터 1회 탭 → 단발 인식 (연속 스캔 안 함)
- [ ] 7. 촬영모드 "인식 중" 프리즈 없음 (Isolate 처리)

**C. 모드 전환 안정성**
- [ ] 8. 자동↔촬영 10회 반복 — 셔터 먹통/"인식중" 잔존/이전 결과 튐 없음
- [ ] 9. 전환 직후 stale 결과 안 튐 (epoch 소유권)

**D. 카메라 생명주기 (예전 P0)**
- [ ] 10. 스캔→홈 복귀 시 카메라 잔상/세로 프리뷰 없음
- [ ] 11. 검정 프리뷰 없음 (진입/이탈 반복·백그라운드→복귀·촬영 중 back)

**E. 최근카드 썸네일 ⚠️(현 빌드 픽스 미포함)**
- [ ] 12. 좌하단 최근등록 썸네일 첫 진입에도 표시(seed) — 양 모드
- [ ] 13. 썸네일 탭 → 자산상세 이동 ← 현 빌드 실패 예상 / 픽스 후 확증
- [ ] 14. 등록 후 그 카드로 썸네일 갱신

**F. 알림 / 딥링크**
- [ ] 15. 게시판 알림 탭 → 게시글 이동 (linkUrl, 백엔드 배포됨)
- [ ] 16. 문의/거래 알림 탭 이동 + 타입별 아이콘 구분

**G. 기타 (복구 기능)**
- [ ] 17. 로그아웃 후 재로그인 시 이전 유저 이미지 캐시 잔존 없음
- [ ] 18. 문의 사진 첨부(다중선택, 최대 5) + 조회
- [ ] 19. 슬랩 판매 게이트 (등급카드 판매 시 슬랩사진 요구)
- [ ] 20. 강제업데이트 게이트 (S3 version.json — ops 설정 시)
- [ ] 21. admin 댓글 body 표시 (확인 완료)

---

## prod write 현황 (이 세션)
- 백엔드 1회 배포(KO_ESTIMATED fix — 되돌릴 예정) · card_external_refs 스키마 · 후쿠오카 카드/매핑(숨김) · SNKRDUNK 시세 40행 · cron 등록 · scanner 벡터 57110 · S3 이미지. 롤백 전부 확보(위).
