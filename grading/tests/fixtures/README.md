# Golden Image Fixtures — AI 그레이딩 안정성 회귀 테스트

## 폴더 구조

```
fixtures/
├── README.md               (이 파일)
└── {card_id}/              (예: zekrom_ex_051)
    ├── expected.json       (사용자가 라벨링한 expected score)
    ├── 1.jpg               (앞면 1)
    ├── 2.jpg               (뒷면 1)
    ├── 3.jpg               (앞면 2 — 다른 각도)
    ├── 4.jpg               (뒷면 2 — 다른 각도)
    └── ...
```

## expected.json 형식

```json
{
  "card_id": "zekrom_ex_051",
  "card_name": "제크로무 ex",
  "shots": [
    {
      "front": "1.jpg",
      "back": "2.jpg",
      "expected_total": 9.0,
      "tolerance": 0.5,
      "notes": "정상 촬영 / 흰 배경 / 밝은 조명"
    },
    {
      "front": "3.jpg",
      "back": "4.jpg",
      "expected_total": 9.0,
      "tolerance": 0.5,
      "notes": "각도 약간 기울어짐"
    }
  ]
}
```

## 사용자 실행 절차

1. 폰으로 같은 카드 앞/뒤 5-10장 촬영 (다양한 각도/조명/거리)
2. `fixtures/{card_id}/` 폴더 생성 + 이미지 drag-drop
3. `expected.json` 작성 (대략 예상 점수 + tolerance)
4. `pytest tests/test_golden_set.py` 실행 → 자동 회귀

## 목표

- 같은 카드 다양한 촬영 = 점수 변동폭 ≤ tolerance (기본 0.5)
- ROI 실패 케이스 = retake_required=True 보장
- 코너 단일 -6.0 같은 false positive 재발 X

## 주의

- prod 이미지 (S3) drop X — local test only
- expected.json 의 tolerance 너무 빡세게 잡지 X (실제 분석 변동 흡수)
- fixture 비어있으면 test_golden_set.py 자동 skip (CI 통과)
