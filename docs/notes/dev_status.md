# 포켓몬 카드 앱 개발 현황

> 마지막 업데이트: 2026-03-30

---

## 앱 개요

**포켓몬 카드 TCG 전용 플랫폼** — 자산관리 + 시세조회 + 개인간 중고 직거래

현재 국내 포켓몬 카드 거래는 네이버 카페/번개장터에 흩어져 있는데,
이걸 하나의 앱으로 통합. 당근마켓처럼 사진 올리고 채팅으로 거래,
내 카드 컬렉션은 주식 포트폴리오처럼 관리, 카드 시세는 차트로 추적.

**기술 스택**
- 백엔드: Spring Boot (Java 17), PostgreSQL, JPA
- 프론트: Flutter (Android/iOS)
- 인증: Kakao OAuth2 + JWT
- 실시간: WebSocket STOMP (예정)

**주요 설정**
| 항목 | 값 |
|------|-----|
| 백엔드 포트 | 8080 |
| DB | postgresql://localhost:5432/pokemon_card_db |
| DB 유저 | nightfury |
| Swagger | http://localhost:8080/swagger-ui.html |
| 카드 이미지 | /Users/nightfury/work_temp/pokemon_card_app/scanner/data/cards |
| 거래 이미지 | /Users/nightfury/work_temp/pokemon_card_app/trade_images |

---

## 레퍼런스 앱

| 앱 | 참고할 점 |
|---|---|
| **당근마켓** | C2C 거래 UX, 채팅, 관심, 신뢰 시스템 |
| **번개장터** | 카드/굿즈 거래 카테고리/필터 구조 |
| **TCGPlayer** (미국) | 포켓몬 카드 특화 마켓, 카드별 시세 그래프, 등급별 가격 |
| **CardLadder** (미국) | 그레이딩 카드 시세 추적, PSA/BGS 등급별 가격 분리 |
| **Pokellector** | 카드 컬렉션 체크리스트 |
| **야후 옥션 (일본)** | 일본 포켓몬 카드 실거래가 기준 |
| **Mavin** (미국) | 카드 스캔 → 가격 즉시 조회 |

---

## 완료된 것 ✅

### 인프라 / 공통
- [x] Spring Boot 백엔드 세팅 (PostgreSQL, JPA, Swagger)
- [x] Kakao OAuth2 로그인 + JWT 발급/검증
- [x] Flutter 프로젝트 세팅 (go_router, dio, fl_chart, image_picker)
- [x] 다크 네이비 디자인 시스템 (`AppColors`)
- [x] 5탭 바텀 네비: 홈 / 시세 / 스캔(중앙 FAB) / 챗 / 내정보

### 카드 데이터
- [x] 카드 마스터 DB (17,932개 카드 + DINOv2 벡터 저장)
- [x] 카드 이미지 서빙 (`/images/cards/**`)
- [x] 가격 수집: ICU 6,698건 + Naver Shopping 29,632건
- [x] `GET /api/cards/market` — 등급 필터, 페이지네이션, latestPrice 포함
- [x] `GET /api/prices/cards/:id/history` — 전체 거래 히스토리

### 자산 관리
- [x] 카드 스캔 (카메라 OCR → ML Kit → 카드 인식)
- [x] 자산 CRUD API + 포트폴리오 요약
- [x] 내 자산 화면, 포트폴리오 화면

### 시세
- [x] 시세 화면 — 정렬(이름/등급/가격/날짜 ↑↓), 등급 단일 필터
- [x] 카드 상세 — 최신 거래가, 최저/최고, 가격 차트 (fl_chart)
- [x] 차트 — 툴팁, Y축 라벨 겹침 방지, 하단 여백, 데이터 1개 처리

### 홈
- [x] 내 카드 + 총 매입가 통합 카드 (총 매입가 + 보유 통계 + 가로 스크롤)
- [x] 판매 중인 카드 피드 섹션 (GET /api/trades)
- [x] HOT 고등급 시세 (가격 상위 30개 중 랜덤 5개)

### 거래 (Trade)
- [x] `trade_posts` DB 테이블
- [x] 판매글 CRUD API (`GET/POST/PUT/DELETE /api/trades`)
- [x] 실물 사진 업로드 (`POST /api/trades/:id/image`, 저장: trade_images/)
- [x] 판매 목록 화면 (`/trades`) — 무한 스크롤
- [x] 판매 등록 화면 (`/trades/create`) — 사진 촬영/선택 + 제목/가격/본문
- [x] 판매글 상세 화면 (`/trades/:tradeId`) — 실물사진 + 정보 + 채팅하기 버튼
- [x] 카드 상세 → "이 카드 판매 중" 목록 + 판매 등록 버튼
- [x] 팩 목록 화면 (`/packs`)

### 기타
- [x] 프로필 화면 (닉네임, 로그아웃)
- [x] 챗 탭 (플레이스홀더)

---

## 해야 할 것 ❌

### 채팅 (최우선 — 거래 핵심)
- [ ] `chat_rooms`, `chat_messages` DB 테이블
- [ ] Spring WebSocket STOMP 설정
- [ ] `POST /api/chats/rooms` — 채팅방 생성 (tradeId 기반)
- [ ] `GET /api/chats/rooms` — 내 채팅방 목록
- [ ] Flutter `web_socket_channel` 연동
- [ ] 챗 탭 — 채팅방 목록 화면
- [ ] 채팅방 화면 — 실시간 메시지 송수신

### 거래 고도화
- [ ] 관심(찜) 기능 — `post_interests` 테이블, 하트 버튼 실제 동작
- [ ] 내가 올린 판매글 목록 (프로필에서 관리)
- [ ] 판매 상태 변경 UI (OPEN → RESERVED → SOLD)
- [ ] 판매글 수정/삭제 UI
- [ ] 거래 완료 → `PriceSnapshot` 자동 생성 (source: "APP", 시세에 반영)

### 알림
- [ ] FCM 푸시 알림 (관심 등록 알림, 채팅 새 메시지 알림)

### 검색
- [ ] 통합 검색 화면 (카드명으로 카드/판매글 동시 검색)

### 기타
- [ ] 구매 이력 / 판매 이력
- [ ] 카드 상세 — 등급별 시세 분리 (생카드 vs PSA10 등)
- [ ] 판매자 프로필 / 거래 후기

---

## API 목록

### 카드
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/cards/{cardId} | 카드 상세 |
| GET | /api/cards/market | 마켓 카드 목록 (등급필터, 페이지) |
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

### 거래
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/trades | 판매 목록 (cardId 필터, 페이지) |
| POST | /api/trades | 판매글 등록 |
| GET | /api/trades/{tradeId} | 판매글 상세 |
| PUT | /api/trades/{tradeId} | 판매글 수정 |
| DELETE | /api/trades/{tradeId} | 판매글 삭제 |
| PATCH | /api/trades/{tradeId}/status | 상태 변경 |
| POST | /api/trades/{tradeId}/image | 사진 업로드 |

### 제품
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/products | 팩 목록 |

### 인증/유저
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/auth/kakao/login | 카카오 로그인 |
| GET | /api/users/me | 내 정보 |
