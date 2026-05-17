class ApiConstants {
  // --dart-define=BASE_URL=http://192.168.x.x:8080 으로 오버라이드 가능
  // 기본값: 시뮬레이터 = localhost, 실기기(USB) = 맥 IP 직접 지정
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static String cardImageUrl(String cardId) => '$baseUrl/images/cards/$cardId.jpg';
  static String tradeImageUrl(String path) => '$baseUrl$path';

  static const String kakaoLogin = '/api/auth/kakao/token';
  static const String cards = '/api/cards';
  static const String prices = '/api/prices/cards';
  static const String assets = '/api/assets';
  static const String gradingAnalyze = '/api/grading/analyze';
  static const String gradingHistory = '/api/grading/history';
  static const String scannerIdentify = '/api/scanner/identify';
  static const String scannerDetect   = '/api/scanner/detect';
}
