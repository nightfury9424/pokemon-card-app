# KREAM 메타몽 프로모 시세 자동 수집

KO 독점 프로모 카드(메타몽 Pokemon Town 2025 등) 시세를 KREAM에서 incremental fetch.

## 운영 모델

```
[매일 21:45 cron]                                 [매일 23:45 cron]
PriceSyncScheduler.syncKreamDittoPromo()          refreshKoEstimatesFromSnapshots()
  │                                                 │
  └─ /Users/.../python/.venv_kream/bin/python       ├─ 일반 카드: SCRYDEX × 환율 × 계수 → KO_ESTIMATED
       /Users/.../python/kream_ditto.py             └─ NO_EN/NO_JP 프로모 카드: KREAM Ungraded 체결가
       │                                                 → KO_ESTIMATED (savePromoKoEstimatedFromKream)
       ├─ Chrome 9222 CDP attach
       ├─ useNuxtApp().$axios로 sales endpoint 페이징
       ├─ 직전 MAX(traded_at) 이후 거래만 incremental fetch
       └─ 5등급(Ungraded/PSA10/9/BRG10/9) → price_snapshots 적층
```

## Chrome 인스턴스 (필수)

### 처음 시작 또는 재시작 시

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/chrome_kream_profile
```

→ 새 별개 Chrome 인스턴스가 뜸 (평소 쓰는 Chrome 영향 X).
- 그 인스턴스에서 KREAM 로그인 1회 (`.env`의 `KREAM_EMAIL` / `KREAM_PASSWORD`)
- `kream.co.kr` 도메인 페이지 1개 열어 두기 (어느 페이지든 OK, 메타몽 페이지 권장)
- **창 닫지 말기** — 닫히면 cron 실패

### 검증

```bash
curl -sS http://localhost:9222/json/version  # 200 + Chrome 버전 출력되면 OK
```

## 수집 정책

- **5등급만**: Ungraded / PSA 10 / PSA 9 / BRG 10 / BRG 9 (BRG 영문·한글은 BRG로 통합)
- 그 외 등급(PSA 8, BRG 8.5/8 등) 응답에 와도 skip
- **Incremental**: `MAX(traded_at) WHERE source='KREAM'` 이후 거래만 INSERT
  - 첫 실행 1회: 전체 누적 거래 (메타몽 5.5개월 ≈ 1,233건 → 5등급만 886건)
  - 이후 매일 cron: 그날 신규 거래만 (보통 5~20건)
- 시각은 응답의 `date_created` UTC 그대로 → KST naive로 변환해 DB 저장
- 같은 날 여러 거래는 chart에서 일별 평균(GROUP BY DATE) 후 표시

## 카드 매핑

| 카드 | DB card_id | KREAM product_id |
|---|---|---|
| 메타몽 Pokemon Town 2025 | `CRD_205C20056CBF48F8B08D` | `508949` |

새 KREAM-거래 카드 추가하려면 `python/kream_ditto.py`의 `CARD_ID` / `PRODUCT_ID` 상수 수정 (현재 단일 카드 PoC).

## price_snapshots 적층 구조

```
source='KREAM'
  ├─ card_status='RAW',    grading_company=NULL, grade_value=NULL    → Ungraded
  ├─ card_status='GRADED', grading_company='PSA', grade_value='10'   → PSA 10
  ├─ card_status='GRADED', grading_company='PSA', grade_value='9'    → PSA 9
  ├─ card_status='GRADED', grading_company='BRG', grade_value='10'   → BRG 10 (영문·한글 합침)
  └─ card_status='GRADED', grading_company='BRG', grade_value='9'    → BRG 9
```

## KO 차트 노출

카드 상세 화면(`front/.../card_detail_screen.dart`)의 KO 탭:
- **칩 3개**: RAW / PSA 10 / PSA 9 (EN/JP와 동일 디자인, 원화)
- **차트**: 선택한 등급의 일별 시계열 (14일 window 통일)
- 데이터 1포인트만이면 14일 전 + 오늘 평탄선 합성

백엔드 응답(`/api/prices/cards/{cardId}/price-summary`)의 `charts.ko`:
```json
{
  "chartType": "LINE",
  "line":      [...]  // Ungraded 시계열
  "psa10Line": [...]  // PSA 10
  "psa9Line":  [...]  // PSA 9
}
```

NO_EN/NO_JP 카드(메타몽)는 자동으로 `findKreamRawSeries` / `findKreamGradedSeries`에서 채움.
일반 카드는 SCRYDEX 기반 기존 경로 그대로.

## 토큰 자동 갱신

`useNuxtApp().$axios`가 KREAM 페이지 안에서 호출되므로:
- 토큰(access_token) 만료 임박 시 KREAM JS가 자동으로 refresh 호출
- 우리는 evaluate 호출 시 살아있는 토큰 자동 사용
- 즉 **Chrome 인스턴스 살아있는 한 무인 운영**

Chrome 닫히면 cron 실패 → 알림(아래) 도착.

## 실패 알림

`PriceSyncScheduler.runWithPython`이 exit code != 0이면 `NotificationService.notifyOpsFailure` 호출:
- `notifications` 테이블에 `type='OPS_PIPELINE_FAILURE'` row 생성
- 어드민 user_id(`app.ops.admin-user-id`)에게 인앱 알림
- 본문에 스크립트 이름 + exit code + 마지막 출력 일부

exit code:
- `2`: CDP attach 실패 (Chrome 9222 꺼짐)
- `3`: KREAM 페이지 없음
- `4`: 응답 구조 변경

## 트러블슈팅

### "Chrome 인스턴스 꺼짐"
앱 알림 받으면 위 "Chrome 인스턴스" 절차로 재시작.

### "차트 일직선 / 평탄선"
- PSA10/9 등 특정 등급의 매일 cron 적층 데이터가 1포인트뿐일 때 14일 평탄선 합성됨.
- 매일 cron 도는 시점에 그 등급 신규 거래 있으면 자연스럽게 시계열 형성.
- 메타몽 PSA 9는 거래량이 낮아 시계열 sparse (정상).

### "수집 안 됨"
1. `curl http://localhost:9222/json/version` — Chrome CDP 살아있는지
2. Chrome 인스턴스 안에 KREAM 페이지 1개 열려있는지
3. 그 페이지에서 로그아웃됐는지 (재로그인 필요)

## 향후 확장

- 다른 NO_EN/NO_JP 프로모 카드 추가 시:
  - `cards` 테이블에 `kream_product_id` 컬럼 추가 또는 별도 매핑 테이블
  - `kream_ditto.py`를 generic 모드로 (DB에서 kream_product_id 있는 카드 순회)
- KREAM 응답에 BRG 9 데이터가 거의 안 와서 자동 적층 X — 자연 누적되면 보임.
- `KREAM_CHART` source는 폐기 (KREAM 일별 종합 가격이라 RAW와 의미 섞임).
