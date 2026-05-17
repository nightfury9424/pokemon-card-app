# 번개장터 학습데이터 파이프라인

## 4단계 워크플로

### 1. 크롤
```bash
python scanner/data/crawl_bunjang.py [페이지수]
```
- 결과: `scanner/data/crawl_raw/crawl_results_2.json` + `crawl_raw/images/`
- seen_pids로 중복 방지, 재실행해도 신규 항목만 추가

### 2. 라벨링
- `localhost:8082/data/label.html` → crawl_results_2.json 불러오기
- 라벨링 후 💾 저장 버튼 → `labeled.json` 다운로드
- 새로고침 전 반드시 저장 (in-memory)

### 3. DB 적용
```bash
python scanner/data/organize_labels.py labeled.json
```
- RAW 이미지 → `scanner/data/realshots/{card_id}/`
- 가격 → `price_snapshots` (source='BUNJANG', card_status='RAW'/'GRADED')
- GRADED 카드는 이미지 복사 안 함

### 4. JSON 정리 (필수)
```python
processed = {r['pid'] for r in labeled if r.get('label') is not None}
clean = [r for r in cr2 if r['pid'] not in processed]
# crawl_results_2.json 덮어쓰기
```
- 처리된 항목 제거해야 다음 세션에서 중복 라벨링 없음

## 현재 상태
- crawl_results_2.json: 5,008개 미라벨 (2026-05-02 기준)
- price_snapshot_id 포맷: `SNAP_` + uuid4().hex[:20].upper()
