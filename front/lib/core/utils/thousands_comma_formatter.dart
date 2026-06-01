import 'package:flutter/services.dart';

/// 천 단위 콤마 포맷팅 (가격 입력용 공통 헬퍼).
///
/// 매수/판매 등록·수정 sheet/화면에서 공통으로 사용.
/// submit 시점에는 `text.replaceAll(',', '')` 후 `int.parse` 해야 함.
String formatThousands(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// TextField 입력 시 천 단위 콤마 자동 삽입.
///
/// 예: `17000` 입력 → `17,000` 표시. `170000` → `170,000`.
/// keyboardType: TextInputType.number와 함께 사용.
class ThousandsCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final value = int.tryParse(raw);
    if (value == null) return oldValue;
    final formatted = formatThousands(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
