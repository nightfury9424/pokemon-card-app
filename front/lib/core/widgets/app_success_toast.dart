import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 토스 스타일 성공 feedback — 화면 가운데 ✓ + 메시지, 1초 fade out.
///
/// 사용:
///   AppSuccessToast.show(context, '자산에 추가됐습니다');
///
/// 흐름:
///   fade-in 220ms → hold 700ms → fade-out 380ms = 약 1.3초
///   HapticFeedback.lightImpact() 자동
///   IgnorePointer — 토스트가 떠 있어도 아래 UI 인터랙션 차단 X
///
/// 적용 대상:
///   스캔 후 "자산에 추가됐습니다"
///   판매/매수 등록 후 "등록되었습니다"
///   그 외 성공 confirmation (에러 메시지는 SnackBar 유지)
class AppSuccessToast {
  static OverlayEntry? _current;

  static void show(BuildContext context, String message) {
    // 중복 호출 시 이전 토스트 즉시 제거 (덮어쓰기)
    _current?.remove();
    _current = null;

    // rootOverlay: pop 후에도 root Navigator의 Overlay에 토스트 유지.
    // _deleteTrade 같은 case (pop 직전 호출)에서 화면이 바뀌어도 토스트 보임.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (_) => _ToastBody(
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

class _ToastBody extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ToastBody({required this.message, required this.onDismiss});

  @override
  State<_ToastBody> createState() => _ToastBodyState();
}

class _ToastBodyState extends State<_ToastBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    // fade: 22% fade-in → 56% hold → 22% fade-out
    _fade = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 22,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 56),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 22,
      ),
    ]).animate(_ctrl);
    // scale: pop-in 효과 (0.86 → 1.0), 그 후 유지
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.86, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 22,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 78),
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
    return Positioned.fill(
      child: IgnorePointer(
        // Material wrap — Overlay 안에서 DefaultTextStyle 없으면 Text가 노란 wavy
        // underline + black 배경으로 보임 (Flutter Material debug 기본).
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => Opacity(
              opacity: _fade.value,
              child: Center(
                child: Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 200,
                      maxWidth: 320,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.green.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: AppColors.green,
                            size: 46,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            height: 1.35,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
