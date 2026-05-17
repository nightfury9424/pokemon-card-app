import 'package:flutter/material.dart';

/// 숫자가 부드럽게 변하는 카운터. 포트폴리오 총액/KO 추정가 같은 핵심 숫자용.
/// REFACTOR_2026-05-12.md 4차-Round1 디자인 polish.
class AnimatedCounter extends StatelessWidget {
  final num value;
  final Duration duration;
  final String Function(num) formatter;
  final TextStyle? style;
  final TextOverflow overflow;
  final int maxLines;

  const AnimatedCounter({
    super.key,
    required this.value,
    required this.formatter,
    this.duration = const Duration(milliseconds: 800),
    this.style,
    this.overflow = TextOverflow.ellipsis,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // 0에서 value까지가 아니라 이전 값에서 새 값으로 자연스럽게.
      tween: Tween<double>(begin: value.toDouble(), end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        formatter(v),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// 값이 변할 때마다 부드럽게 보간하는 카운터. setState로 value 변경 시 자동 애니메이션.
class TweenedCounter extends StatefulWidget {
  final num value;
  final Duration duration;
  final String Function(num) formatter;
  final TextStyle? style;
  final TextOverflow overflow;
  final int maxLines;

  const TweenedCounter({
    super.key,
    required this.value,
    required this.formatter,
    this.duration = const Duration(milliseconds: 900),
    this.style,
    this.overflow = TextOverflow.ellipsis,
    this.maxLines = 1,
  });

  @override
  State<TweenedCounter> createState() => _TweenedCounterState();
}

class _TweenedCounterState extends State<TweenedCounter> {
  late num _displayed;

  @override
  void initState() {
    super.initState();
    _displayed = widget.value;
  }

  @override
  void didUpdateWidget(covariant TweenedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _displayed = oldWidget.value;
      // 새 값으로 트윈 트리거
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _displayed = widget.value);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: _displayed.toDouble(),
        end: widget.value.toDouble(),
      ),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        widget.formatter(v),
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      ),
    );
  }
}
