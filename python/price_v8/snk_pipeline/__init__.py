"""SNKRDUNK_JP 가격 파이프라인 (dry-run · 로컬 전용).

scrydex JP 를 SNKRDUNK 일본 실거래로 감시·검증·보정하는 신규 보조 가격 소스.
설계 정본: docs/SNK_PRICE_PIPELINE_DESIGN.md

모듈:
  config              공통 상수 (경로·환율·임계)
  db                  로컬 SQLite 스키마 (approved_mapping / snk_snapshot / review_queue)
  snk_client          SNK sales-chart/detail fetch
  load_mapping        working CSV → approved_mapping, approve/reject 승인게이트
  collector_dryrun    approved 카드 SNK 수집 → snk_snapshot
  detector_dryrun     snk_snapshot vs scrydex ladder → review_queue

★ prod DB write 0 · 가격 반영 0 · 운영 반영은 별도 세션(백업+승인 후).
"""
