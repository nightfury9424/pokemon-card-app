import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/theme/app_colors.dart';

/// 시세 안내 공지 모달 (B2-16).
/// 가격이 알고리즘 예상가치임을 개발자 톤으로 고지. 공지 팝업 표준 패턴:
///  - 하단 "오늘 하루 보지 않기" **체크박스** + 확인 버튼.
///  - 체크 후 닫으면 오늘 다시 안 뜸(날짜 저장). 체크 없이 닫으면 다음 진입에 다시 노출.
///  - 한 세션 내 중복 노출 방지(_shownThisSession).
class PriceDisclaimer {
  static const _storage = FlutterSecureStorage();
  static const _key = 'price_disclaimer_date';
  static bool _shownThisSession = false;

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// 공지 표시 판단. 날짜는 "오늘 하루 보지 않기" 체크 시에만 기록.
  static Future<void> maybeShow(BuildContext context) async {
    try {
      if (_shownThisSession) return;
      final hiddenDate = await _storage.read(key: _key);
      if (hiddenDate == _today()) {
        _shownThisSession = true; // 오늘은 체크로 숨김 — 재조회 막기
        return;
      }
      _shownThisSession = true;
      if (!context.mounted) return;
      final dontShowToday = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _PriceDisclaimerDialog(),
      );
      // 체크하고 닫았을 때만 오늘 날짜 기록 → 오늘 다시 안 뜸.
      if (dontShowToday == true) {
        await _storage.write(key: _key, value: _today());
      }
    } catch (_) {
      // silent — 안내 실패는 앱 흐름에 영향 없음.
    }
  }
}

class _PriceDisclaimerDialog extends StatefulWidget {
  const _PriceDisclaimerDialog();

  @override
  State<_PriceDisclaimerDialog> createState() => _PriceDisclaimerDialogState();
}

class _PriceDisclaimerDialogState extends State<_PriceDisclaimerDialog> {
  bool _dontShow = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.blueLight, size: 22),
                SizedBox(width: 8),
                Text('시세 안내',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '현재 국내 포켓몬 카드 실거래 데이터가 충분하지 않아, '
              'PokeFolio는 국내외 시세와 카드별 정보를 바탕으로 '
              '예상가치를 계산하고 있어요.\n\n'
              '실제 거래가와 차이가 있을 수 있지만, 여러분들의 거래와 관심이 '
              '쌓일수록 더 정확한 시세를 함께 만들어갈 수 있다고 생각합니다.\n\n'
              '부족한 부분은 계속 개선해나가겠습니다. 많은 이용 부탁드립니다.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13.5, height: 1.65),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('PokeFolio 개발자 올림',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 18),
            // 공지 팝업 패턴: 하단 체크박스 + 확인 버튼.
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _dontShow = !_dontShow),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _dontShow
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 20,
                            color: _dontShow
                                ? AppColors.blue
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text('오늘 하루 보지 않기',
                              style: TextStyle(
                                  color: _dontShow
                                      ? AppColors.textSecondary
                                      : AppColors.textMuted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_dontShow),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('확인',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
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
