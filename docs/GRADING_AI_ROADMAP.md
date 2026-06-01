# 그레이딩 AI 로드맵

> 작성: 2026-05-21
> 정책: **베타 출시 전엔 알고리즘/ML 코드 수정 금지**. 본 문서는 베타 이후 작업 계획만 정리.

## 정책 결정 — 왜 베타 전엔 코드 수정 X

베타 직전 시점에 알고리즘을 만지면 다음과 같은 위험이 큼:
- 오판 샘플이 충분치 않아 변경의 효과 측정 불가
- 회귀 위험 (이미 v2.1에서 표면 최솟값 4.0 / 센터링 최솟값 5.0 등 가드레일이 누적된 상태)
- 실제 PSA/BRG 등급 검증 dataset 부재 → 변경의 옳고 그름 판단 불가
- ML 도입은 dataset 자체가 prerequisite

**베타 단계 = dataset 수집 기간.** 베타 사용자가 capture하는 사진과 신고/피드백이 모델 학습의 원천. 그 시점까지 코드는 그대로 두고, 출시 후 모은 데이터로 개선.

오해 방지 layer는 출시 전 `Tier 1 UI/UX` (commit `316ff049`)에서 끝남:
- AI 예측 명시
- 외부 등급사 아님 명시
- `certNumber` 라벨 분기 (APP- prefix는 "앱 분석 ID")
- 상시 disclaimer
- 친화적 실패 UX

---

## 현재 상태 (v2.1, analyzer.py 기준)

| 영역 | 가중치 | 방법 | 알려진 한계 |
|------|--------|------|-------------|
| 센터링 | 15% | Sobel 그라디언트 argmax | **아트워크 내부 그라디언트를 카드 엣지로 오인** 빈번. `quality_lowest` 계산에서 제외 + 최솟값 5.0 클램프로 땜빵 |
| 코너 | 35% | Canny 엣지 밀도 (중앙 50%) | 비교적 안정. 단, capture 화면 70% 가이드 미준수 시 오감지 |
| 표면 | 25% | Laplacian std (테두리 5%) | **아트영역 구김/눌림/인쇄 결함 미감지** (테두리만 봄). 최솟값 4.0 클램프 |
| 백화 | 25% | HSV S≤10, V≥210 (뒷면 + 4 코너) | 깨끗 카드 ratio ≈ 0.0065. 비교적 안정 |

**총점**: 가중 합 + `heavy_whitening=True`이면 ×0.85 페널티. PSA 매핑: 9.5+ = PSA10, 8.0~9.4 = PSA9 …

### 자체 명시된 한계 (GRADING_DEV.md 우선순위 항목)

1. **센터링**: Sobel argmax 오감지 → 카드 테두리 색상 기반 탐지로 교체 필요 (방향: 노랑/파랑 색상 분리 + 전환점 탐지)
2. **표면**: 테두리 5%만 분석 → 아트영역 구김/눌림 미감지
3. **홀로그래픽**: SAR/SSR 반사 → 표면 스크래치 오인 가능

### 검증 데이터 부재

- 자체 점수와 **실제 PSA/BRG 등급** 비교 set 없음
- "PSA 9 카드인데 우리는 7.5로 찍힌다" 같은 오판 case 정리되지 않음
- 같은 카드를 다시 찍으면 같은 점수가 나오는지 일관성 측정 없음

---

## Phase 1 — 오판 샘플 수집 (베타 운영 ~ 4주)

베타 사용자 capture에서 학습 가능한 형태로 데이터 축적.

| 항목 | 어떻게 |
|------|--------|
| capture 원본 보존 | 이미 `assets/{id}/grading` 엔드포인트가 front/back 이미지 첨부. assetGradingImages 디렉토리에 보존 |
| 사용자 신고 채널 | "이 점수 이상해요" 1-tap 신고 버튼. 결과 화면 또는 카드 상세 메타 row에서 진입 |
| 실제 등급 입력 (선택) | 사용자가 외부 PSA/BRG 받은 결과를 입력하면 보상/배지. 자체 점수 ↔ 실제 등급 pair 누적 |
| 일관성 측정 | 같은 자산에 그레이딩 여러 번 돌렸을 때 점수 분포. assetGradingResults 테이블에 timestamp + 점수 누적 |

**목표 dataset 규모**: PSA/BRG 실제 등급 라벨 카드 **최소 300장**, 사용자 신고 오판 **최소 200건**. 그 미만이면 ML 진입 무의미.

---

## Phase 2 — Heuristic 개선 (dataset 일부 모인 뒤)

ML 진입 전 단계. 현재 OpenCV 기반 알고리즘에서 오판 패턴을 보고 룰 수정.

### 우선순위 A
- **센터링 Sobel → 색상 기반 교체**: 카드 테두리 노랑/파랑 색상 분리 (HSV 또는 LAB) + 전환점 탐지로 물리적 엣지 위치 결정. 아트워크 내부 그라디언트 오인 차단.

### 우선순위 B
- **표면 분석 영역 확장**: 현재 테두리 5% → 아트영역 포함. 단, 카드 디자인 자체(반사 디테일, 음영)를 결함으로 오인하지 않게 mask 필요.
- **홀로그래픽 mask**: SAR/SSR/CHR 등 holo 카드에서 반사 영역을 표면 분석에서 제외. rarity 필드 + 색상 분포 기반 holo 영역 detect.

### 우선순위 C
- **capture 품질 validation**: 분석 진입 전 사진이 흐릿/기울어짐/플래시 반사를 사전 거부. confidence 자체보다 더 명확한 게이트.

---

## Phase 3 — ML 도입 (dataset 충분히 모인 뒤)

| 모델 | 입력 | 출력 | 학습 데이터 |
|------|------|------|-------------|
| Defect Detector | 카드 ROI crop | bbox + 결함 카테고리 (스크래치/구김/오염) | 사용자 신고 + 라벨러 작업 |
| Centering Regressor | 카드 ROI | 4-방향 마진 비율 | 라벨러 작업 |
| Holo Mask Segmenter | 카드 ROI | binary mask (holo / non-holo) | 자동 약지도 + 일부 수작업 |
| Final Score Calibrator | 4 sub-score + meta | PSA 등급 확률 분포 | PSA/BRG 실제 등급 pair |

### 기술 스택 후보
- **Detector**: YOLO v8 small / RT-DETR (스캐너에서 이미 사용 중인 YOLO 라이브러리 재사용)
- **Segmenter**: U-Net 또는 SAM zero-shot prompt
- **Calibrator**: LightGBM 또는 단순 MLP (sub-score → PSA 확률)
- **Serving**: 기존 grading FastAPI에 모델 endpoint 추가. ONNX runtime 또는 PyTorch CPU 추론.

### 데이터셋 요구사항
- Defect Detector: **약 1,000장 라벨링** (사용자 신고에서 시드)
- Centering: **약 500장 라벨링**
- Holo Mask: **약 300장 약지도 + 100장 수작업**
- Calibrator: **PSA/BRG 라벨 페어 300장 ~ 1,000장**

---

## 안전 가드 — 변경 시 회귀 방지

| 가드 | 내용 |
|------|------|
| pin test set | 깨끗한 near-mint 카드 10장 + 손상 카드 10장. 어떤 변경이든 이 set 점수 분포 유지 |
| A/B 비교 모드 | analyzer 호출 시 `version=v2.1` / `v3` 등 선택. 사용자에겐 v2.1 결과 노출하고 v3는 shadow 로그만 |
| 사용자 노출 시점 | shadow 단계 1~2주 + 통계 비교 → 회귀 없으면 default 변경 |

---

## 무관한 영역 — 본 로드맵 범위 밖

- 그레이딩 capture UX (촬영 가이드 overlay, 미리보기, 재촬영) — `L2 촬영 가이드 overlay` 별도 작업
- 그레이딩 결과 표시 UI — `Tier 1`에서 완료 (commit `316ff049`)
- 거래 상세/호가에 estimatedGrade 표시 — 정책상 노출 X (Codex 권장 유지)
- 외부 등급사(PSA/BRG) cert# 직접 검증 API 연동 — 베타 후 사업 결정 영역

---

## 다음 즉시 작업 (베타 출시까지)

본 로드맵 작성 후 grading 영역에서 **코드 수정은 진행하지 않음**. 다음 작업:

1. **채팅 MVP 전수조사** → MVP plan → 구현 (베타 거래 흐름 prerequisite)
2. **그레이딩 L2 capture overlay** (촬영 가이드 / 미리보기 / 재촬영 UX) — 알고리즘 무관, UX만
3. 출시 후 **Phase 1 dataset 수집 인프라** (신고 채널, 실제 등급 입력 UI)

본 로드맵은 Phase 1 이후 시점에 재진입.
