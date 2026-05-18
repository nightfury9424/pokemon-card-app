/// 가격을 한국식 콤마 + "원"으로 포맷팅. 호가 위젯들 공통 사용.
String formatKrw(int v) {
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  final body = buf.toString();
  return '${v < 0 ? '-' : ''}$body원';
}
