import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 점검 중 전체 화면 — 백엔드 점검/배포 다운타임 시 앱 전역 게이트([MaintenanceGate])가 노출.
/// 백엔드와 독립된 정적 maintenance.json 기반이라 백엔드 완전 다운 상태에서도 표시됨.
class MaintenanceScreen extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const MaintenanceScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.build_circle_outlined,
                    color: AppColors.blue, size: 60),
                const SizedBox(height: 22),
                const Text(
                  '점검 중입니다',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    side: const BorderSide(color: AppColors.blue),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  ),
                  child: const Text('다시 시도',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
