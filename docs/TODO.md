# 포켓폴리오 TODO

## 🔴 신고/민원 관리 (미구현)

거래 사기 신고 처리 기능. 아래 순서로 작업.

### 1. DB 테이블 (직접 실행 필요 — ddl-auto: validate)
```sql
CREATE TABLE reports (
    report_id     VARCHAR(50)  PRIMARY KEY,
    trade_id      VARCHAR(50)  NOT NULL,
    reporter_id   VARCHAR(50)  NOT NULL,
    reason        VARCHAR(50)  NOT NULL,  -- FRAUD / FALSE_INFO / SPAM / MISC
    detail        TEXT,
    status        VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    admin_memo    TEXT,
    created_at    TIMESTAMP    NOT NULL,
    updated_at    TIMESTAMP    NOT NULL
);
CREATE INDEX idx_reports_trade_id ON reports(trade_id);
CREATE INDEX idx_reports_status   ON reports(status);
```

### 2. 백엔드
- `Report` 엔티티 + `ReportRepository`
- `AdminController`에 신고 목록/상태변경 API 추가
  - `GET /api/admin/reports` (PENDING 우선 정렬)
  - `PATCH /api/admin/reports/{id}/status` (REVIEWED / RESOLVED / DISMISSED)
  - `PATCH /api/admin/reports/{id}/memo` (관리자 메모)

### 3. 어드민 ERP
- 사이드바에 "신고 관리" 메뉴 추가 (🚨 아이콘)
- 신고 목록 테이블: 신고ID / 거래글 / 신고자 / 사유 / 접수일 / 상태
- 처리 액션: 경고 / 거래글 삭제 / 계정 정지 / 기각

### 4. Flutter 앱
- 거래글 상세 화면에 "신고하기" 버튼
- 신고 사유 선택 바텀시트 (사기 / 허위매물 / 스팸 / 기타)
- `POST /api/reports` 호출

---

## 🔴 Flutter 프론트 재구성

- 전반적인 UI/UX 재설계 필요
- 거래 기능 개발 여부 재확인 후 포함 범위 결정

---

## 🔴 시세 데이터 추가 수집

- 번개장터 크롤링 데이터 추가 적재 필요
- enScrydexRef 매핑 카드 확대 → 계수 샘플 수 증가
- scrydex_scraper.py 완성 후 정기 실행 검증

---

## ✅ 완료

- 어드민 ERP (대시보드 / 카드 / 유저 / 거래 / 시세 / 스캐너)
- 한국 시장 계수 동적 갱신 (매일 새벽 4:30 자동 재계산)
- 계수 히스토리 그래프
- DINOv2 파인튜닝 파이프라인

---

## ✅ 2026-05-09 완료

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

## 🟡 우선순위 높음 (다음 세션)

- [ ] `price_ebay.py` 실제 동작 검증 (eBay API 호출 테스트)
- [ ] `price_scrydex.py` guard 실운영 검증 (--days 3 으로 돌려서 이상 감지 로그 확인)
- [ ] 새로 추가된 3개 카드 scrydex 가격 수집 (메가개굴닌자 EX, 메가지가르데 EX, 뮤 VMAX)
- [ ] scrydex_mapper.html 잔여 미매핑 카드 처리 (437개)
- [ ] `price_anomalies` 테이블 KO_ESTIMATED 재계산 트리거 (오염 기각 시 이전 값 유지 로직 확인)

## 🟡 중기

- [ ] NAVER_CAFE 번들 감지 로직 (레어도 2개+ 묶음 매물 필터링)
- [ ] eBay API 직접 시세 수집 파이프라인 (`price_ebay.py` 기반 확장)
- [ ] 관리자 웹 판초 피카츄류 수동 cleanup SQL 버튼 (retroactive contamination cleaner)
