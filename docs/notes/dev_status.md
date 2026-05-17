# 포켓몬 카드 앱 개발 현황

> 마지막 업데이트: 2026-05-09

---

## 앱 개요

**포켓몬 카드 TCG 전용 플랫폼** — 자산관리 + 시세조회 + 개인간 중고 직거래 + 카드 스캔 인식

---

## 기술 스택

| 항목 | 버전/값 |
|------|--------|
| 백엔드 | Spring Boot 4.0.4, Java 20, port 8080 |
| DB | PostgreSQL 14, `nightfury` / `pokemon_card_db` |
| 프론트 | Flutter 3.41.4 (iOS) |
| 인증 | Kakao OAuth2 + JWT |
| 그레이딩 | FastAPI, port 8081 |
| 스캐너 | FastAPI + DINOv2+FAISS, port 8082 |
| Swagger | http://localhost:8080/swagger-ui.html |
| 카드 이미지 | `/Users/fury/pokemon-card-app/scanner/data/cards/` |
| 거래 이미지 | `/Users/fury/pokemon-card-app/trade_images/` |

---

## 레퍼런스 앱

| 앱 | 참고할 점 |
|---|---|
| **당근마켓** | C2C 거래 UX, 채팅, 관심, 신뢰 시스템 |
| **번개장터** | 카드/굿즈 거래 카테고리/필터 구조 |
| **TCGPlayer** | 포켓몬 카드 특화 마켓, 카드별 시세 그래프 |
| **CardLadder** | 그레이딩 카드 시세 추적, PSA/BRG 등급별 가격 분리 |
| **Mavin** | 카드 스캔 → 가격 즉시 조회 |

---

## 완료된 것 ✅

### 인프라 / 공통
- [x] Spring Boot 백엔드 (PostgreSQL, JPA, Swagger)
- [x] Kakao OAuth2 로그인 + JWT
- [x] Flutter 프로젝트 (go_router, dio, fl_chart, image_picker)
- [x] 다크 네이비 디자인 시스템 (`AppColors`)
- [x] 5탭 바텀 네비: 홈 / 시세 / 스캔(중앙 FAB) / 챗 / 내정보

### 카드 데이터
- [x] 카드 마스터 DB — 9,728장 (C/U/R 제외)
- [x] 카드 이미지 EN/JP/KO ~10,237장 (`scanner/data/cards/`)
- [x] 이미지 서빙: 로컬 → scrydex CDN fallback (`CardImage` 위젯)
- [x] `GET /api/cards/market` — 등급 필터, 페이지네이션, latestPrice 포함
- [x] `GET /api/prices/cards/:id/history` — 거래 히스토리
- [x] scrydex EN/JP 시세 실시간 연동 (`ScrydexLiveClient`, 2시간 캐시)
- [x] KO 예상가 계산 (EN scrydex × 환율 × 계수)

### 자산 관리
- [x] 자산 CRUD API + 포트폴리오 요약
- [x] 내 자산 화면, 포트폴리오 화면

### 시세
- [x] 시세 화면 — 정렬(이름/등급/가격/날짜 ↑↓), 등급 단일 필터
- [x] 카드 상세 — 최신 거래가, 최저/최고, 가격 차트 (fl_chart)

### 홈
- [x] 내 카드 + 총 매입가 통합 카드
- [x] 판매 중인 카드 피드 섹션
- [x] HOT 고등급 시세 (가격 상위 30개 중 랜덤 5개)

### 거래 (Trade)
- [x] 판매글 CRUD API
- [x] 실물 사진 업로드
- [x] 판매 목록(무한스크롤) / 등록 / 상세 화면

### 스캐너 ← 2026-05 완성
- [x] FAISS DB 구축 — 7,192 벡터, 3,491 카드
- [x] FastAPI 서버 (port 8082, DINOv2+FAISS)
- [x] Spring Boot `ScannerController` 연동
- [x] Flutter 실시간 스캔 UI (`imageStream`, 셔터 없음)
- [x] macOS OpenMP 충돌 수정 (`OMP_NUM_THREADS=1` + `run_in_executor`)

### 그레이딩
- [x] FastAPI 서버 (port 8081)
- [x] 센터링/코너/표면/백화 배점 알고리즘

### 기타
- [x] 프로필 화면 (닉네임, 로그아웃)
- [x] 실시간 채팅 (WebSocket STOMP — `stomp_dart_client`)


### 2026-05-09 완료
- [x] 리스트/상세 KO 예상가 일치 (popularityMultiplier 제거 — list/detail 동일 공식 적용)
- [x] scrydex JP slug가 EN column에 잘못 저장된 3개 카드 수정 (비크티니, 라티아스 ex, 뮤 ex RR)
- [x] 메가리자몽Y ex MUR KO 예상가 수정 (509,680원 → 775,050원 — stale SCRYDEX_JP 삭제 후 재계산)
- [x] 마켓 목록 DISTINCT ON 버그 수정 (같은 이름/레어도 다른 세트 카드가 누락되던 문제 — CardRepository 전체 쿼리에서 DISTINCT ON 제거)
- [x] 수동 카드 3개 추가 (메가개굴닌자 EX MUR, 메가지가르데 EX MUR, 뮤 VMAX HR)
- [x] 어드민 카드 추가 모달 개선 (officialCode/scrydexRef 하나만 입력 → 백엔드가 pokemoncard.co.kr 또는 scrydex 스크랩해서 자동완성)
- [x] `GET /api/admin/cards/lookup` — KO/EN/JP 타입별 외부 소스 조회 (Jsoup)
- [x] scrydex 가격 오염 보호장치 (`price_ebay.py` + `price_scrydex.py` guard)
  - PSA10 70% 급락 또는 PSA grade 역전 감지 시 eBay Finding API로 교차검증
  - 오염 확인 시 PSA10 저장 스킵
- [x] `price_anomalies` 테이블 + 어드민 웹 가격 이상 알림 페이지 (`/alerts`)
  - 사이드바 미해결 건수 배지
  - eBay 검증 결과 표시 + "해결됨" 버튼
- [x] 판초 피카츄 (리자몽 X) PSA10 오염 데이터 수동 정리 ($22,000 → $695 → 복원)

---

## 해야 할 것 ❌

### 스캐너 2단계
- [ ] 번개장터/당근마켓 체결 게시글 크롤링
- [ ] 실사 이미지로 DINOv2 파인튜닝 (NT-Xent Contrastive Loss)
- [ ] `price_snapshots` 자동 적재

### 거래 고도화
- [ ] 관심(찜) 기능 — `post_interests` 테이블
- [ ] 판매 상태 변경 UI (OPEN → RESERVED → SOLD)
- [ ] 거래 완료 → `price_snapshots` 자동 생성 (source: "APP")

### 알림
- [ ] FCM 푸시 알림 (채팅 새 메시지, 관심 알림)

### 검색
- [ ] 통합 검색 화면 (카드명으로 카드/판매글 동시 검색)

### 기타
- [ ] 카드 상세 — 등급별 시세 분리 (생카드 vs PSA10)
- [ ] 구매/판매 이력
- [ ] 판매자 프로필

---

## API 목록

### 카드
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/cards/{cardId} | 카드 상세 |
| GET | /api/cards/market | 마켓 카드 목록 |
| GET | /api/cards/product/{productId} | 팩 카드 목록 |

### 자산
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/assets | 내 자산 목록 |
| POST | /api/assets | 자산 등록 |
| PUT | /api/assets/{assetId} | 자산 수정 |
| DELETE | /api/assets/{assetId} | 자산 삭제 |
| GET | /api/assets/portfolio | 포트폴리오 요약 |

### 시세
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/prices/cards/{cardId}/history | 거래 히스토리 |
| GET | /api/scrydex/prices/{ref} | scrydex 실시간 |
| GET | /api/prices/coefficient | 환율·계수 |

### 거래
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/trades | 판매 목록 |
| POST | /api/trades | 판매글 등록 |
| GET | /api/trades/{tradeId} | 판매글 상세 |
| PUT | /api/trades/{tradeId} | 판매글 수정 |
| DELETE | /api/trades/{tradeId} | 판매글 삭제 |
| PATCH | /api/trades/{tradeId}/status | 상태 변경 |
| POST | /api/trades/{tradeId}/image | 사진 업로드 |

### 스캐너
| Method | Path | 설명 |
|--------|------|------|
| POST | /api/scanner/identify | 카드 인식 |

### 그레이딩
| Method | Path | 설명 |
|--------|------|------|
| POST | /api/grading/analyze | 등급 분석 |

### 인증/유저
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/auth/kakao/login | 카카오 로그인 |
| GET | /api/users/me | 내 정보 |
