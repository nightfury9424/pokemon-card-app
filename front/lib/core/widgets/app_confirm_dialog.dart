import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 공통 confirm 다이얼로그 — 토스 스타일 (UI polish 2026-05-19).
///
/// Material AlertDialog default 제거:
/// - 모서리 radius 16
/// - 헤더 17px w700 / 본문 14px w400 line-height 1.5
/// - 액션 row divider top + 50/50 분할 + height 52
/// - destructive (삭제 등) confirm은 red, 일반은 blue
/// - 좌측 취소 (textSecondary) / 우측 confirm (color + w700)
///
/// 사용:
///   final ok = await AppConfirmDialog.show(
///     context,
///     title: '판매글 삭제',
///     message: '삭제하면 되돌릴 수 없습니다.',
///     confirmLabel: '삭제',
///     destructive: true,
///   );
///   if (ok == true) { ... }
class AppConfirmDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String cancelLabel = '취소',
    String confirmLabel = '확인',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.divider),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: cancelLabel,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      onTap: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  Container(width: 1, color: AppColors.divider),
                  Expanded(
                    child: _ActionButton(
                      label: confirmLabel,
                      color: destructive ? AppColors.red : AppColors.blue,
                      fontWeight: FontWeight.w700,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final FontWeight fontWeight;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.fontWeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 52,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: fontWeight,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}
