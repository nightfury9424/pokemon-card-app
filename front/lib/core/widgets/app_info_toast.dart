import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 토스 스타일 안내/주의 feedback — 화면 가운데 ⓘ + 메시지, fade out.
/// AppSuccessToast/AppErrorToast 패턴 동일, info용으로 color/icon만 분기.
///
/// 사용:
///   AppInfoToast.show(context, '판매 전 앱 등급 분석이 필요합니다');
///
/// 흐름:
///   fade-in 280ms → hold 940ms → fade-out 280ms = 약 1.5초
///   HapticFeedback.selectionClick() — 안내용 조용한 햅틱 (error의 lightImpact 대비 ↓)
///   IgnorePointer — 토스트가 떠 있어도 아래 UI 인터랙션 차단 X
///
/// 적용:
///   사용자 행동 안내/제약 ("판매 전 등급 분석 필요", "감정사 선택", ...)
///   에러 X / 성공 X — 빨간 ⚠ 부적절 + 녹색 ✓ 부적절한 케이스
class AppInfoToast {
  static OverlayEntry? _current;

  static void show(BuildContext context, String message) {
    _current?.remove();
    _current = null;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (_) => _InfoToastBody(
        message: message,
        onDismiss: () {
          if (_current != null) {
            _current?.remove();
            _current = null;
          }
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
    HapticFeedback.selectionClick();
  }
}

class _InfoToastBody extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  const _InfoToastBody({required this.message, required this.onDismiss});

  @override
  State<_InfoToastBody> createState() => _InfoToastBodyState();
}

class _InfoToastBodyState extends State<_InfoToastBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fade = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 19,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 62),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 19,
      ),
    ]).animate(_ctrl);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.86, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 19,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 81),
    ]).animate(_ctrl);
    _ctrl.forward().whenComplete(widget.onDismiss);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 1 hotfix #2: Material ancestor 추가 — Overlay에 직접 insert 시
    // Material 부재로 Text가 default debug underline (노란 이중 밑줄) 표시되는 문제 fix.
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: _buildContent(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.blue.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.blue,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
