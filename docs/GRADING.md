# 그레이딩 서비스

## 구조

```
grading/
├── main.py       # FastAPI (port 8081)
├── analyzer.py   # GradingAnalyzer — 핵심 알고리즘
├── models.py     # AnalysisResult
└── venv/
```

```bash
cd grading && source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8081
```

---

## API

```
POST /api/grading/analyze   (multipart/form-data)

files[0]  앞면 전체
files[1]  뒷면 전체
files[2~5]  앞 코너 (좌상/우상/좌하/우하)
files[6~9]  뒤 코너 (좌상/우상/좌하/우하)
```

---

## 알고리즘 v2.1 배점

| 항목 | 가중치 | 방법 |
|------|--------|------|
| 센터링 | 15% | Sobel 그라디언트 위치 기반 마진 측정 |
| 코너 | 35% | Canny 엣지 밀도 (중앙 50% 영역) |
| 표면 | 25% | Laplacian std (테두리 5% 영역) |
| 백화 | 25% | HSV 분석 (S≤10, V≥210 조건) |

`heavy_whitening=True`이면 총점 × 0.85 페널티.

---

## 핵심 로직 요약

- `_find_card_in_image()`: Otsu 이진화 → 카드 컨투어 감지. 실패 시 반전(`bitwise_not`)으로 재시도
- 센터링: `quality_lowest` 계산에서 제외 (오감지 빈번). 최솟값 5.0
- 표면: 최솟값 4.0 (배경 노이즈 과감점 방지)
- 백화: 깨끗한 카드 ratio≈0.0065 → 9.4점

---

## PSA 등급 대응

| PSA | 점수 |
|-----|------|
| 10 | 9.5+ |
| 9 | 8.0~9.4 |
| 8 | 6.5~7.9 |
| 7 | 5.0~6.4 |
| 6↓ | 5.0 미만 |

---

## 개선 필요 항목

- **센터링**: Sobel argmax 오감지 빈번 → 카드 테두리 색상 기반 탐지로 교체 권장
- **표면**: 아트워크 구김/눌림 미감지 (현재 테두리만)
- **홀로그래픽**: SAR/SSR 반사 → 표면 스크래치 오인 가능

---

## 촬영 권장 조건

흰 종이 단색 배경, 플래시 OFF, 카드가 화면 70% 이상 차지.
