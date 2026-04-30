# 포켓몬 카드 앱 — 개발 현황

> 마지막 업데이트: 2026-04-30

---

## 스택

| 구분 | 기술 |
|------|------|
| 백엔드 | Spring Boot 4.0.4 (Java 20), PostgreSQL 14, port 8080 |
| 프론트 | Flutter 3.41.4 (iOS 우선), go_router, fl_chart |
| 인증 | Kakao OAuth2 + JWT |
| 스캐너 AI | Ollama llava (로컬/서버, port 11434) |
| 그레이딩 | Python FastAPI (port 8081) + OpenCV |

---

## 완료된 기능 ✅

### 인프라 / 공통
- [x] Spring Boot 백엔드 (PostgreSQL, JPA, Swagger)
- [x] Kakao OAuth2 로그인 + JWT 발급/검증
- [x] Flutter 프로젝트 (go_router, dio, fl_chart, camera)
- [x] 다크 네이비 디자인 시스템 (`AppColors`)
- [x] 5탭 바텀 네비: 홈 / 시세 / 스캔 / 등급 / 내정보

### 카드 데이터
- [x] 카드 마스터 DB — KO 17,599장
- [x] scrydex JP/EN 이미지 매핑 (JP 1,250장 + EN 1,719장)
- [x] 이미지 우선순위: JP scrydex → EN scrydex → 카드 뒷면
- [x] `resolveCardImageUrl()` 전역 함수 (`card_image.dart`)
- [x] pokemonkorea.co.kr 이미지 차단 (저작권)

### 시세 파이프라인
- [x] scrydex 스크래퍼 — JP/EN RAW 히스토리 + eBay 실거래가
- [x] price_snapshots: SCRYDEX_JP / SCRYDEX_EN / EBAY / APP source
- [x] 매일 새벽 3시 자동 동기화 (`PriceSyncScheduler`)
- [x] 한국 예상 가치 계수 (~0.515, KO:EN 비율 기반)
- [x] 3라인 차트 (KO/JP/EN) + 기간 토글 (7d/30d)
- [x] `GET /api/scrydex/prices/{ref}` — scrydex 시세 직접 조회

### 자산 관리
- [x] 자산 CRUD API (`/api/assets`)
- [x] 포트폴리오 요약 API (`/api/assets/portfolio`)
- [x] 자산 화면 — 카드 목록 + 총 평가금액
- [x] 컬렉션 볼 뱃지 (몬스터볼/슈퍼볼/하이퍼볼/마스터볼)

### 시세 화면
- [x] 시세 목록 — 등급 필터, 정렬(이름/등급/가격)
- [x] `GET /api/cards/market?sortBy=price` — LATERAL JOIN 가격순
- [x] 카드 상세 — KO/EN/JP 시세 탭 + 차트

### 스캐너 (카드 인식)
- [x] ML Kit OCR → **Ollama Vision AI (llava)** 전환 완료
- [x] 후면 카메라 풀스크린 프리뷰 (veryHigh 해상도)
- [x] 1.5초 자동 촬영 → `/api/scanner/identify` 호출
- [x] 수록번호 인식 → DB 조회 → 카드 반환
- [x] 인식 성공 시 하단 모달 (카드 이미지 + 이름 + 레어도 + 수량 조절)
- [x] 모달에서 **자산 등록** / **상세 보기** / **계속 스캔** 버튼
- [x] 그린 코너 가이드 오버레이

### 등급 분석 (Grading)
- [x] Python FastAPI 그레이딩 서비스 (port 8081)
- [x] 10장 사진 기반 분석 (앞면/뒷면 + 코너 8장)
- [x] 센터링 / 코너 마모 / 표면 스크래치 / 화이트닝 → 종합 점수
- [x] **v2.1**: 검정 배경 대응 (반전 이진화 fallback) + 표면 점수 최솟값 4.0 보정
- [x] Spring Boot 그레이딩 컨트롤러 (`/api/grading/analyze`)
- [x] Flutter 등급 탭 — 10단계 촬영 가이드 화면 + 결과 화면
- [x] 촬영 힌트: 밝은 단색 배경 안내 포함
- [x] 결과 화면: 점수별 색상 + 분석 사유 표시 + 점수 범위 표시
- [x] 분석 결과 DB 저장 제거 (분석 후 바로 반환)

### 거래 (초기 버전 → 현재 비활성)
- [x] trade_posts 테이블 + CRUD API
- [x] 채팅 (WebSocket STOMP) 기초 구현
- [x] 현재 앱에서 거래/채팅 진입점 제거됨 (재설계 예정)

---

## 현재 앱 탭 구성

| 탭 | 화면 | 상태 |
|----|------|------|
| 홈 | 총 자산 + 보유 카드 목록 | ✅ |
| 시세 | 카드 시세 목록 + 상세 | ✅ |
| 스캔 | Ollama 카드 인식 + 자산 등록 | ✅ |
| 등급 | 10장 촬영 → 등급 점수 분석 | ✅ |
| 내정보 | 프로필 + 로그아웃 | ✅ |

---

## 다음 우선순위 ❌

### 스캐너 고도화 (아이디어 정리 예정)
- [ ] Ollama 첫 호출 로딩 10~20초 UX 개선
- [ ] 카드가 DB에 없는 경우 대응 (PR 카드, 해외판 등)
- [ ] 동일 카드 연속 스캔 시 API 재호출 방지 (캐싱)
- [ ] 스캐너 정확도 향상 방안

### 거래 재설계 (2차)
- [ ] C2C 거래 플로우 재설계
- [ ] 포트폴리오 공개/비공개 설정
- [ ] 판매 의사 설정 + 탐색
- [ ] 채팅방 + 거래 완료 처리

### 기타
- [ ] FCM 푸시 알림 (시세 변동, 채팅)
- [ ] 업적 시스템 (컬렉터 티어)
- [ ] 통합 검색

---

## API 목록 (현재 활성)

### 카드
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/cards/{cardId} | 카드 상세 |
| GET | /api/cards/market | 시세 목록 (등급필터, 가격순) |
| GET | /api/cards/product/{productId} | 팩별 카드 목록 |
| GET | /api/cards/number/{collectionNumber} | 수록번호로 조회 |

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
| GET | /api/scrydex/prices/{ref} | scrydex 실시간 조회 |

### 스캐너
| Method | Path | 설명 |
|--------|------|------|
| POST | /api/scanner/identify | 이미지 → 카드 인식 (Ollama llava) |

### 그레이딩
| Method | Path | 설명 |
|--------|------|------|
| POST | /api/grading/analyze | 10장 사진 → 등급 점수 분석 |

### 인증/유저
| Method | Path | 설명 |
|--------|------|------|
| GET | /api/auth/kakao/login | 카카오 로그인 |
| GET | /api/users/me | 내 정보 |
