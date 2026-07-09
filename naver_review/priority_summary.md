# NAVER 검수 우선순위 요약
- 전체 1362 → **PRIORITY(네가 볼 것) 444** / AUTO_REJECT 472 / SOURCE_MISSING 446
- PRIORITY 고유카드 199장, card_id별 묶음으로 `review_v2_priority.html`에서 검수.
- URL없음 446 → SOURCE_EVIDENCE_MISSING(제외), 고가/중요만 NEEDS_MANUAL_SOURCE.
- DIRTY auto_reject: {'REJECT_SEALED': 24, 'REJECT_BUNDLE': 126, 'REJECT_GRADED': 290, 'REJECT_OVERSEAS_OR_JP_QUOTE': 31, 'REJECT_BUY_POST': 1}
- 정렬: 고위험+고가+앱가괴리 score순. VALID_SINGLE_RAW만 v8 ground truth.
