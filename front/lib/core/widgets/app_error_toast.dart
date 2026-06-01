import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 토스 스타일 에러 feedback — 화면 가운데 ⚠ + 메시지, fade out.
/// AppSuccessToast 패턴 동일, 에러용으로 color/icon/duration만 분기.
///
/// 사용:
///   AppErrorToast.show(context, '서버에 일시적 문제가 발생했습니다.');
///
/// 흐름:
///   fade-in 320ms → hold 1.15s → fade-out 320ms = 약 1.8초
///   HapticFeedback.lightImpact() 자동
///   IgnorePointer — 토스트가 떠 있어도 아래 UI 인터랙션 차단 X
///
/// 적용:
///   ApiClient.setErrorHandler 5xx/network/auth 자동 에러
///   사용자 작업 실패 (등록/삭제 등 — Material SnackBar 일괄 교체 대상)
class AppErrorToast {
  static OverlayEntry? _current;

  static void show(BuildContext context, String message) {
    // 중복 호출 시 이전 토스트 즉시 제거 (덮어쓰기)
    _current?.remove();
    _current = null;

    // rootOverlay: pop 후에도 root Navigator의 Overlay에 토스트 유지.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (_) => _ErrorToastBody(
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
    HapticFeedback.lightImpact();
  }
}

class _ErrorToastBody extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorToastBody({required this.message, required this.onDismiss});

  @override
  State<_ErrorToastBody> createState() => _ErrorToastBodyState();
}

class _ErrorToastBodyState extends State<_ErrorToastBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // 에러는 좀 더 오래 — 1.8초 (success 1.3초 대비 ↑)
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    // fade: 18% fade-in → 64% hold → 18% fade-out
    _fade = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 64),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 18,
      ),
    ]).animate(_ctrl);
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.86, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 82),
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
    // AppSuccessToast 패턴과 일치.
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
          color: AppColors.red.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.red,
            size: 36,
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
