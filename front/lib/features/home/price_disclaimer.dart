import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/theme/app_colors.dart';

/// 일일 시세 안내 모달 (B2-16).
/// 가격이 알고리즘 예상가치임을 하루 1회 고지. 오늘 이미 봤으면 skip.
class PriceDisclaimer {
  static const _storage = FlutterSecureStorage();
  static const _key = 'price_disclaimer_date';

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// 하루 1회 표시. 표시 시점에 날짜 기록(= 오늘 1회 보장).
  static Future<void> maybeShow(BuildContext context) async {
    try {
      final shown = await _storage.read(key: _key);
      if (shown == _today()) return;
      await _storage.write(key: _key, value: _today());
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _PriceDisclaimerDialog(),
      );
    } catch (_) {
      // silent — 안내 실패는 앱 흐름에 영향 없음.
    }
  }
}

class _PriceDisclaimerDialog extends StatelessWidget {
  const _PriceDisclaimerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.info_outline_rounded, color: AppColors.blueLight, size: 22),
                SizedBox(width: 8),
                Text('시세 안내',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'PokeFolio의 가격은 국내외 시세를 기반으로 한 '
              '알고리즘 예상가치예요. 실제 거래가와 차이가 있을 수 있으니 '
              '참고용으로 활용하시고, 정확한 시세는 직거래 시 직접 확인해 주세요.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13.5, height: 1.6),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                      ),
                      child: const Text('오늘 하루 보지 않기',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                      ),
                      child: const Text('확인',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
