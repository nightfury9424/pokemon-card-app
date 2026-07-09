# SNKRDUNK 프로모 차트 노출 — 백엔드 설계 (미적용, 후속 배포)

## 문제
NO_EN/NO_JP 프로모(메타몽 등)의 상세 차트 `rawLine/psa10Line/psa9Line` 은
`GlobalPriceService` NO_EN/NO_JP 분기(≈L1993-2007)에서 **`source='KREAM'` 전용**
쿼리 `PriceSnapshotRepository.findKreamGradedSeries`(L236-245, `source='KREAM'` 하드코딩)
로만 채워진다. → SNKRDUNK 스냅샷을 넣어도 차트 미표시.

- 헤드라인 KO 예상가(RAW) = `getDisplayPrice`=KO_ESTIMATED → **이미 노출됨**(변경 불필요).
- PSA10/PSA9/RAW **차트 라인**만 백엔드 변경 필요.

## 선택지

### A안 (권장·최소 변경) — source 필터 확장
한 카드는 KREAM 또는 SNKRDUNK **한 소스만** 스냅샷을 가짐(둘이 안 섞임).
→ 쿼리의 `source='KREAM'` 을 `source IN ('KREAM','SNKRDUNK')` 로만 넓히면 됨. 라우팅 로직 불필요.

```java
// PriceSnapshotRepository.findKreamGradedSeries → 이름/필터만 일반화
@Query(nativeQuery = true, value = """
    SELECT TO_CHAR(traded_at,'YYYY-MM-DD') AS d, AVG(price)::bigint AS price
    FROM price_snapshots
    WHERE card_id = :cardId AND source IN ('KREAM','SNKRDUNK')
      AND grading_company = :company AND grade_value = :grade
      AND traded_at > :after
    GROUP BY 1 ORDER BY 1 ASC
    """)
List<Object[]> findPromoGradedSeries(...);   // 호출부 그대로
```
- RAW 라인(Ungraded)은 `grading_company IS NULL` 경로 — 그쪽도 동일하게 source IN (...) 로.
- 영향: 메타몽(KREAM)은 결과 불변(SNKRDUNK 스냅샷 없음). SNKRDUNK 프로모만 신규 노출.
- additive·저위험. 배포 후 후쿠오카 차트 검증.

### B안 (명시적) — 카드별 source 라우팅
`card_external_refs` 로 카드의 프로모 소스를 판별해 `:source` 파라미터 주입.
더 명확하지만 코드/쿼리 시그니처 변경 큼. 소스 3개 이상 될 때 채택.

## 배포 순서(후속)
1. A안 쿼리 확장 (읽기 전용, additive)
2. 로컬/스테이징에서 후쿠오카 상세 차트에 RAW/PSA10/PSA9 3라인 뜨는지 확인
3. 메타몽 차트 회귀 없는지(값 동일) 확인
4. prod 배포 (백엔드 재빌드 — 시세 로직 무관, 조회 쿼리만)

## 주의
- ladder 비정상(후쿠오카 RAW>PSA9) → 차트는 실측 3라인 그대로. 정렬/보정 금지.
- 백필 apply 는 이 노출 경로 확정 후 or 병행 가능(저장은 노출과 독립).
