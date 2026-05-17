import 'dart:math' as math;

/// KO 시세 표시 정책 (2026-05-16 결정, 17:15 단순화).
///
/// 저가 카드(원천가가 작은 카드)는 작은 금액 변동이 퍼센트/차트에서 과장됨.
/// 표시 단계에서 차단하는 정책 (백엔드 raw값은 그대로 유지).
///
/// 단일 임계 — lastPrice 또는 prevPrice 중 하나라도 5,000원 미만 → 등락 통째 숨김.
/// 5,000원 이상은 0.1%라도 실제 변동 표시. diff==0은 숨김.
/// Stage D 차트 y축 최소 range = max(1,000원, 대표가 * 0.3) — 유지.
///
/// 가디안 V "전일 대비 0원 (-18.8%)" 버그 방지 — diff/percent 같은 기준으로 통합.
/// docs/PRICE_POLICY_2026_05_16.md 참조.
class PriceDisplayPolicy {
  static const int percentThreshold = 5000;
  static const double chartMinRange = 1000;
  static const double chartMinRangeRatio = 0.3;

  /// lastPrice 또는 prevPrice 중 하나라도 임계 미만 → 등락 숨김.
  static bool shouldHideChange({required int lastPrice, required int prevPrice}) =>
      lastPrice < percentThreshold || prevPrice < percentThreshold;

  /// 차트 y축 범위 조정.
  /// dataMin/dataMax이 minRange보다 좁으면 중앙값 기준 확장.
  /// minY는 절대 0 미만으로 내려가지 않음 (가격은 음수 불가).
  static ChartRange adjustChartRange({
    required double dataMin,
    required double dataMax,
    required double representativePrice,
  }) {
    final base = dataMax - dataMin;
    final minRange = math.max(
      chartMinRange,
      representativePrice * chartMinRangeRatio,
    );
    if (base >= minRange) {
      final minY = math.max(0.0, dataMin * 0.88);
      final maxY = dataMax * 1.12;
      return ChartRange(minY, maxY);
    }
    final center = (dataMin + dataMax) / 2;
    final minY = math.max(0.0, center - minRange / 2);
    final maxY = minY + minRange;
    return ChartRange(minY, maxY);
  }

  /// 전일 대비 표시 모델 생성.
  /// null 반환 = 등락 영역 자체 숨김.
  /// 가디안 V 버그 방지: diff/percent 한 함수에서 같은 기준으로 계산.
  ///
  /// [showZero] true (기본, 리스트 친화): 5,000원 이상 + diff==0이면 "0원 (0.0%)" 표시
  ///            false (카드 상세 친화): diff==0이면 null
  static PriceChangeDisplay? buildChangeDisplay({
    required int? lastPrice,
    required int? prevPrice,
    String prefix = '전일 대비',
    bool showZero = true,
  }) {
    if (lastPrice == null || prevPrice == null || prevPrice <= 0) return null;
    // 단일 임계: 둘 중 하나라도 5,000원 미만 → 등락 통째 숨김
    if (shouldHideChange(lastPrice: lastPrice, prevPrice: prevPrice)) return null;

    final diff = lastPrice - prevPrice;
    if (diff == 0 && !showZero) return null;

    final percent = diff / prevPrice * 100;
    final sign = diff > 0 ? '+' : (diff < 0 ? '-' : '');
    final diffStr = '$sign${_formatAbsPrice(diff)}원';
    final percentStr = '$sign${percent.abs().toStringAsFixed(1)}%';
    final labelBase = '$diffStr ($percentStr)';
    final color = diff > 0
        ? PriceChangeColor.positive
        : (diff < 0 ? PriceChangeColor.negative : PriceChangeColor.neutral);
    return PriceChangeDisplay(
      label: prefix.isEmpty ? labelBase : '$prefix $labelBase',
      diff: diff,
      percent: percent,
      color: color,
    );
  }

  /// 음수 처리 분리 — abs 후 콤마 포맷, sign은 호출부에서.
  /// 1의 자리 반올림은 기존 정책 유지 (10원 단위).
  static String _formatAbsPrice(int value) {
    final absValue = value.abs();
    final rounded = (absValue / 10).round() * 10;
    return rounded.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}

/// 차트 y축 범위.
class ChartRange {
  final double minY;
  final double maxY;
  const ChartRange(this.minY, this.maxY);
}

/// 전일 대비 표시 색상 키 (UI에서 AppColors로 매핑).
enum PriceChangeColor { positive, negative, neutral }

/// 전일 대비 표시 모델.
class PriceChangeDisplay {
  final String label;
  final int diff;
  final double? percent;
  final PriceChangeColor color;

  const PriceChangeDisplay({
    required this.label,
    required this.diff,
    required this.percent,
    required this.color,
  });
}
