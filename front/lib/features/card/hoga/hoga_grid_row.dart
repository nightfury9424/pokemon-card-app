import 'package:flutter/material.dart';

/// 토스증권식 3-column grid 호가 row.
///
/// 모든 호가 row(ASK/BID/Pivot)가 같은 [centerWidth]를 공유해서 가격 column이
/// 동일 x축에 정렬된다.
///
/// ```
/// ┌─────────────┬─────────────┬─────────────┐
/// │ left (flex) │ center 고정 │ right (flex) │
/// └─────────────┴─────────────┴─────────────┘
/// ```
///
/// - ASK row: left = count+bar (우→좌), right = 빈
/// - BID row: left = 빈, right = count+bar (좌→우)
/// - Pivot row: left = label, center = 큰 가격, right = 보조 정보
class HogaGridRow extends StatelessWidget {
  final Widget left;
  final Widget center;
  final Widget right;
  final double centerWidth;
  final double height;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final BoxBorder? border;

  const HogaGridRow({
    super.key,
    required this.left,
    required this.center,
    required this.right,
    this.centerWidth = 124,
    this.height = 32,
    this.onTap,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final body = SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(child: left),
          SizedBox(width: centerWidth, child: Center(child: center)),
          Expanded(child: right),
        ],
      ),
    );
    final wrapped = (backgroundColor != null || border != null)
        ? DecoratedBox(
            decoration: BoxDecoration(color: backgroundColor, border: border),
            child: body,
          )
        : body;
    return onTap == null ? wrapped : InkWell(onTap: onTap, child: wrapped);
  }
}
