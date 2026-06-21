# [OPEN/P1] 스캐너 같은-포켓몬 구분력 한계 → hard-negative DINOv2 v2 (4장 스캔 보류)

**생성**: 2026-06-22 · **상태**: OPEN · **차단 대상**: 신규 4장 스캔 + 향후 같은포켓몬 V/ex/VMAX/AR 추가

## 1. 문제 한 줄
현 DINOv2 파인튜닝 임베딩이 **같은 포켓몬·다른 카드(V/ex/VMAX/AR)를 실제 스캔 노이즈 하에서 구분 못 함**. 클린 이미지는 구분되나(코사인 0.56~0.77), 노이즈 폰스캔에서 near-tie로 붕괴 → 신규 카드가 기존 카드 스캔을 끌어감.

## 2. 스캔 보류 4장 (allowlist=`scanner/scanner_excluded_cards.json`)
| card_id | 카드 | 혼동 기존카드 |
|---|---|---|
| CRD_555EE842647815F48715 | 엘풍 ex SR | 엘풍 V SR |
| CRD_C25940958F57A0DE60C8 | 메타몽 V SSR | 메타몽 VMAX SSR |
| CRD_7EFC022C360ECB18F368 | 코바르온 AR | 코바르온 SR |
| CRD_07838391EB0EE31C2240 | 러브로스 V CSR | 아세로라의 장난 SAR |

★ **DB·앱 검색·상세·가격은 정상 노출**. 스캐너 벡터에서만 제외(인덱스 3889 = 3840+49). 스캔 시 비슷한 기존 카드가 나올 수 있음(인식 안 됨 보장 X).

## 3. 증거 (회귀 8건)
- scan_capture 707→700, 8건이 기존카드→신규카드로 뒤집힘 (엘풍V→ex ×4, 메타몽VMAX→V ×2, 코바르온SR→AR ×1, 아세로라→러브로스V realshot ×1)
- ★진단 결정타: **8건 전부 신규클린 > 정답실사진 > 정답클린** → 엘풍 V 스캔이 *진짜 엘풍 V 실사진*보다 *엘풍 ex 클린*에 더 가깝게 임베딩. 모델이 카드 정체성보다 포켓몬 일러 유사성을 더 봄.

## 4. 실패한 빠른 해결책 (전부 회귀 0 못 만듦)
| 시도 | 결과 |
|---|---|
| OCR rerank(번호 disambiguate) | 8/8 OCR 번호 추출 실패(빈값/오독). 스캔에서 번호 못 읽음 |
| rot+7 증강 제거 | 신규 다른 벡터가 또 이김 |
| 카드별 합의 점수(top-2/3 avg·outlier 제외) | 신규가 여러 벡터로 광범위 우세 (튀는1개 아님) |
| **실사진 augment10 인덱스 추가**(20장) | 양쪽 추가·정답쪽만 추가 둘다 실패. 데이터 추가로 안 풀림 |

→ **인덱스 데이터 레벨 해결 소진. 모델 임베딩 자체 업그레이드만 남음.**

## 5. 해결책 = hard-negative metric learning v2 (별도 브랜치·별도 승인)
- 현 DINOv2 파인튜닝 = **base freeze**, projection head 또는 last block만 학습
- **Positive**: 같은 카드 KO/JP/EN/실사진 끌어당김
- **Hard-negative**: 같은포켓몬 다른카드/레어도 밀어냄 (+ 위 4쌍 명시 + FAISS 최근접 타카드 자동 mining)
- **카드 단위 train/val 분리**(실사진 데이터 누수 방지) · 전체 3893 재임베딩 · 고정 회귀셋 old/new A/B
- (확장) 2단계: FAISS Top-K → patch/local reranker
- ★"데이터 충분=수시간" 단정 금지: train/val 분리·누수방지 설계 후 판단

## 6. 가용 학습 데이터 (시드)
- `~/Downloads/realshots_crops.json` (8종 20장, 크롭 완료) — v2 positive/hard-neg 시드
- `scanner/realshot_crop_tool.html` (추가 수집용 크롭 툴)
- 기존 `data/scan_captures`(713) + `data/realshots`(496) = 회귀 검증셋

## 7. 4장 재등록 게이트 (v2 통과 시)
1. v2 모델로 전체 재임베딩 후 회귀셋에서 **exact base 대비 신규 회귀 0**
2. 4장 KO/JP/EN 원본 Top-1 정상
3. 8건 회귀 정답 유지
4. allowlist에서 4장 제거 + 인덱스 3893 hot-swap

## 8. 관련 도구·산출물 (scanner/)
`ab_consensus.py`(합의 A/B) · `reg8_forensic.py`(벡터단위 포렌식) · `realshot_experiment.py`+`realshot_diag.py`(실사진 실험·진단) · `gate_49.py`(49 배포 게이트) · `scanner_excluded_cards.json`(allowlist)
