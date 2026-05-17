# API 비용 최적화 — 패턴 정리

## 원칙

- **API 호출은 mutation이 발생했을 때만** — 단순 화면 이동/뒤로가기로 리로드 금지
- **이미 받은 데이터는 재활용** — 상위 화면에서 받아온 데이터를 하위 화면에 넘겨 zero-latency 렌더링
- **silent refresh** — 리로드 시 로딩 스피너 없이 기존 데이터 유지하며 백그라운드 갱신

---

## 패턴 1 — Mutation-Aware Refresh

화면을 나갈 때 CUD(Create/Update/Delete)가 실제로 발생했을 때만 상위 화면이 리로드.

### 구현
```dart
// 하위 화면: mutation 발생 시 pop(true)
context.pop(true);

// 상위 화면: push 후 결과 확인
final changed = await context.push<bool>('/some/screen', extra: {...});
if (changed == true && mounted) _loadData();
```

### 적용 위치
| 파일 | 설명 |
|------|------|
| `asset_screen.dart` | `_modified` 플래그 + `PopScope` → 카드 등록/삭제 시만 홈에 알림 |
| `scanner_screen.dart` | `_wasModified` 플래그 → 자산 등록 성공 시만 `pop(true)` |
| `home_screen.dart` | `/assets`, `/scanner` push 후 `changed == true`일 때만 `_loadData()` |
| `card_detail_screen.dart` | 거래/등급 push 후 `changed == true`일 때만 `_loadData()` |
| `trade_list_screen.dart` | 생성/상세 push 후 `changed == true`일 때만 `_loadTrades()` |
| `grading_capture_screen.dart` | result 화면에서 `pop(true)` 받으면 `pop(true)` 전파 |

---

## 패턴 2 — Zero-Latency Image Fallback

상위 화면(리스트)에서 이미 받아온 카드 데이터를 하위 화면(상세)에 넘겨, API 응답 전에도 이미지 즉시 렌더링.

### 구현 (card_detail_screen.dart)
```dart
// 상위에서 받은 asset 데이터를 로컬 상태로 보관
Map<String, dynamic>? _localAsset;

@override
void initState() {
  _localAsset = widget.myAsset; // asset_screen에서 이미 받아온 데이터
  _loadData();                  // 병렬로 최신 데이터 fetch
}

// 카드 이미지 렌더링: API 응답 전에는 _assetCard 사용
final _assetCard = _localAsset?['card'] is Map
    ? Map<String, dynamic>.from(_localAsset!['card'] as Map)
    : null;
final data = _cardDetail ?? widget.cardData ?? _assetCard; // fallback chain
```

### 비용
- 추가 API 호출 없음 — 이미 받은 데이터 재활용
- 이미지는 Flutter 이미지 캐시로 중복 다운로드 없음

---

## 패턴 3 — Silent Refresh

리로드 시 로딩 스피너를 띄우지 않고 기존 데이터를 유지하며 백그라운드에서 갱신. UX 끊김 없음.

### 구현 (home_screen.dart)
```dart
Future<void> _loadAll({bool silent = false}) async {
  if (!silent) setState(() => _loading = true);
  // ... fetch ...
  setState(() { _loading = false; /* update data */ });
}

// 화면 복귀 시 silent refresh
_loadAll(silent: true);
```

---

## 패턴 4 — Optimistic Local Update (삭제)

삭제 API 성공 후 서버 재조회 없이 로컬 상태만 업데이트. 포트폴리오 합계도 클라이언트에서 재계산.

### 구현 (asset_screen.dart)
```dart
await _api.delete('/api/assets/$assetId');
setState(() {
  _modified = true;
  _assets.removeWhere((a) => a['assetId'] == assetId);
  final newMarketValue = _assets.fold<double>(
    0, (sum, a) => sum + ((a['marketValue'] as num?)?.toDouble() ?? 0));
  _portfolio = {
    'totalCards': _assets.length,
    'distinctCardCount': _assets.map((a) => a['cardId']).toSet().length,
    'totalMarketValue': newMarketValue,
  };
});
```

### 주의
- 서버 오류 시 롤백 필요 (현재는 try-catch로 처리)
- `_loadPortfolio()` 재호출 금지 — 서버 응답에 `totalMarketValue` 없을 수 있음

---

## API 호출 빈도 요약

| 화면 | 최초 진입 | 화면 복귀 | mutation 후 |
|------|-----------|-----------|-------------|
| home_screen | O | silent | O |
| asset_screen | O | X (PopScope) | O (내부 CUD만) |
| card_detail_screen | O | X | O (등급/거래 변경 시) |
| trade_list_screen | O | X | O (생성/삭제 시) |
| scanner_screen | X | X | — |
