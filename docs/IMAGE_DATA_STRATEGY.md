# 이미지 데이터 전략 (스캔 캡처 → 카탈로그/AI moat)

> 2026-06-03 확정. Claude + Codex(실파일 18개 grep) 교차검증.
> 핵심: **한 번의 스캔이 (A)고퀄 한국 카드 이미지 + (B)스캔 라벨 데이터 둘 다 생성.**

## WHY — 왜 우리 이미지가 필요한가
- **scrydex SPOF 2곳**: 카탈로그(`resolveCardImageUrl`→S3 `cards/v1`+hotlink) + 스캐너 FAISS 인덱스(`scanner` 가 scrydex 다운로드 `{cardId}_{lang}.png`). 정책변경/종료 시 둘 다 붕괴 + 저작권(닌텐도 파생) 리스크.
- **KO 네이티브 부재**: 인덱스가 jp/en ref로만 빌드 → 한글판 레퍼런스 0.
- **도메인 갭**: `build_db.py` augment = 밝기±55·회전±7도뿐(슬리브/글레어/배경 없음) → 실촬영 매칭 취약.
- **moat + 수요신호**: 유저 KO 실사진 corpus = 복제불가 자산. 스캔빈도 = 수요지표.

## 현재 HOW (실측)
- 카탈로그: `resolveCardImageUrl` → S3 `cards/v1`(scrydex 파생) → scrydex CDN → 뒷면.
- 스캐너: scrydex 다운로드 → `{cardId}_{lang}.png` → FAISS(15,559장, KO 없음). `card_db.faiss`+`card_meta.json` startup 로드(핫스왑 가능).
- `asset_images`(asset→cardId, FRONT/BACK, S3): 유저 실사진 쌓이는 중 **활용 0**.

## 목표 HOW (우선순위)
| P | 작업 | 임팩트/구현 | 코드변경 |
|---|---|---|---|
| P1 | FAISS multi-ref 보강 | 大/小 | `card_db.faiss` 재빌드만 (main.py 무변경) |
| P2 | 카탈로그 swap | 大/中 | S3 `cards/v1`에 파일 투입 (resolveCardImageUrl 무변경) |
| P3 | 수요신호 분석 | 中/小 | 스캔 이벤트 로깅 |

## 저장 설계
- **신규 테이블 `scan_captures`** (asset_images와 분리): capture_id, user_id, card_id, s3_key, source_type(SCAN), match_confidence, image_quality(NULL허용), blur_score, is_catalog_candidate, is_faiss_indexed, consent_version, created_at, deleted_at.
- **S3**: `scan_captures/{userId}/{id}.jpg`(private, ImageProxyController JWT) / 승격본 `catalog_candidates/{cardId}/` 별도 복사(원본 보존).
- **품질지표 = 저장 후 서버 배치**(앱 무변경, 기준변경 재처리 가능). 캡처 시 NULL.
- **PIPA**: consent_version 스냅샷 / 탈퇴=soft delete + S3 purge(30일 유예) / **★카드 warp-crop만 저장**(손·배경 제거).

### 용량 효율 (★무한 증식 차단 — 유저수 무관 상한 고정)
- **리사이즈+압축**: warp-crop → **~1024px JPEG q82 (~150~300KB)**. 백엔드 저장 직전. (DINOv2/카탈로그 모두 충분)
- **★카드당 캡처 cap ~20장**: 초과 시 신규가 기존 최저품질보다 높으면 교체, 아니면 skip. 저장 전 `SELECT count WHERE card_id` 체크.
- **라이프사이클**: REJECTED/미사용 30일 만료, promoted 영구.
- **상한 추정**: 3,451 KO × 20 × 250KB ≈ ~17GB(S3 월 ~$0.5). cap 없으면 viral 카드 하나가 수백 GB.

### 관리자 커버리지 가시화 (FF2 admin)
- **KO 자체이미지 커버리지 %**: `catalog_source=USER_SCAN` 카드 / 전체 KO 노출 — 세트·레어도별 분해 (scrydex 탈출 milestone 추적)
- **수집 퍼널**: scan_captures 총 / candidate / indexed / promoted
- **카드별 수집 현황**: 카드당 캡처 수(승격 가능 카드 식별)
- 데이터 모델 지원 필요: `cards.catalog_source`(또는 promoted 조인) + scan_captures 카드별 count. Phase1부터 카운터 축적.

## 결정 (락)
- 동의 = ToS **일괄동의**. 출시 범위 = **스캔 캡처만**.
- **warp-crop만 저장(a안)**: 스캐너 identify가 warp 결과를 응답에 포함(작은 변경) → 백엔드가 그 crop 저장. full-frame 저장 금지(배경노이즈+PIPA).
- **dual-use, 단 카탈로그 승격 기준 ≫ FAISS 포함 기준**.
- scrydex 탈출 = milestone(KO 커버리지 50/80/95%), hybrid(있으면 우리것/없으면 scrydex). 인덱스는 scrydex anchor 유지 + 유저 ref 추가.

## 사용 플랜 (단계)
- **Phase 1 (출시)**: 스캔 성공 → warp-crop 업로드 + `scan_captures` 저장(품질 NULL). 스캐너 인덱스 무변경. UX 무변화, 데이터 축적 시작. + ToS 일괄동의 문구.
- **FF1 (D+2~4주)**: 품질 배치 채우기 + `build_db.py`로 FAISS multi-ref 보강(main.py 무변경).
- **FF2 (D+1~2개월)**: 큐레이션 admin → 카탈로그 swap(KO 우선순위 추가), scrydex 점진 탈출.

관련: [[project-image-system-s3]] [[project-launch-roadmap-2026-06-03]]
