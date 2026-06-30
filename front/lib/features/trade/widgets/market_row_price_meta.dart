import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class MarketRowPriceMeta extends StatelessWidget {
  final int? price;

  /// 가격 출처 라벨(PriceLabel.resolve 결과). '한국판 예상가'(기본)·빈값은 행에서 숨기고,
  /// '해외 참고가'·'시세 준비중'·'한국판 거래가' 같은 예외 출처만 작은 라벨로 표시.
  final String priceLabelText;

  /// 변동액 칩(예: '-15,100원'). null = 등락 숨김(저가 정책 등).
  final String? changeAmount;

  /// 퍼센트 칩(예: '(-36.6%)'). null 가능.
  final String? changePct;
  final Color changeColor;

  const MarketRowPriceMeta({
    super.key,
    required this.price,
    required this.priceLabelText,
    required this.changeAmount,
    required this.changePct,
    required this.changeColor,
  });

  static const double _gap = 6.0;

  /// 대다수 카드의 기본 라벨 → 행에서 숨김(목록 일관성). 다른 가격 출처는 그대로 노출.
  static const String _hiddenDefaultLabel = '한국판 예상가';

  @override
  Widget build(BuildContext context) {
    final priceStr = price != null ? AppColors.formatPrice(price!) : '시세 없음';
    // 변동액·퍼센트는 항상 한 묶음(절대 분리 X): "-15,530원 (-37.9%)".
    final String? changeStr = changeAmount == null
        ? null
        : (changePct == null ? changeAmount! : '$changeAmount $changePct');

    // 라벨: 기본('한국판 예상가')·빈값 → 숨김. 예외 출처(해외 참고가/시세 준비중/한국판 거래가) → 표시.
    final trimmed = priceLabelText.trim();
    final String? label =
        (trimmed.isEmpty || trimmed == _hiddenDefaultLabel) ? null : trimmed;

    final priceStyle = TextStyle(
      color: price != null ? AppColors.textSecondary : AppColors.textMuted,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    const labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    final changeStyle = TextStyle(
      color: changeColor,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );

    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(builder: (ctx, c) {
      final maxW = c.maxWidth;
      // 가격·변동값은 '원자'(한 줄·미분리). 극단 글자배율서만 per-element scaleDown(전체 행 아님).
      final priceAtom = _atom(priceStr, priceStyle);
      final priceW = _measure(priceStr, priceStyle, scaler);
      final labelW = label == null ? 0.0 : _gap + _measure(label, labelStyle, scaler);

      // 변동값 없음 → 가격(+예외 라벨)만.
      if (changeStr == null) return _priceLine(priceAtom, label, labelStyle);

      final changeW = _measure(changeStr, changeStyle, scaler);

      // ① 한 줄: 가격 (+예외 라벨) + 변동액·퍼센트.
      if (priceW + labelW + _gap + changeW <= maxW - 6) {
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            priceAtom,
            if (label != null) ...[
              const SizedBox(width: _gap),
              Flexible(fit: FlexFit.loose, child: _labelText(label, labelStyle)),
            ],
            const SizedBox(width: _gap),
            _atom(changeStr, changeStyle),
          ],
        );
      }

      // ② 폭 부족 → 2줄: 1줄=가격(+예외 라벨), 2줄=변동액·퍼센트(★한 묶음·한 줄 유지).
      // 변동값은 maxLines:1·softWrap:false(원자) → 퍼센트 단독 줄바꿈 불가. 극단 폭만 per-element scaleDown.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _priceLine(priceAtom, label, labelStyle),
          const SizedBox(height: 2),
          _atom(changeStr, changeStyle),
        ],
      );
    });
  }

  // 가격(+예외 라벨) 한 줄. 라벨 없음 → 가격 원자 단독(부모 폭 제약 시 극단만 scaleDown).
  // 라벨 있음 → 가격·라벨을 loose Flexible 로 → 극단 폭선 가격이 scaleDown, 라벨은 clip(숫자 보존).
  Widget _priceLine(Widget priceAtom, String? label, TextStyle labelStyle) {
    if (label == null) return priceAtom;
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Flexible(fit: FlexFit.loose, child: priceAtom),
        const SizedBox(width: _gap),
        Flexible(fit: FlexFit.loose, child: _labelText(label, labelStyle)),
      ],
    );
  }

  Widget _labelText(String s, TextStyle style) => Text(s,
      maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style);

  // 숫자 원자: 한 줄(maxLines:1·softWrap:false) 유지, 분리/줄바꿈 금지. 부모가 폭을 제약하는 위치
  // (2줄의 각 줄/한 줄 단독 가격)에선 극단 글자배율서만 per-element scaleDown(전체 행 아님)으로
  // 한 줄·전체 숫자 보존(ellipsis 없음).
  Widget _atom(String s, TextStyle style) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(s, maxLines: 1, softWrap: false, style: style),
      );

  static double _measure(String s, TextStyle style, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: scaler,
    )..layout();
    return tp.width;
  }
}
