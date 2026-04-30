class ApiConstants {
  static const String baseUrl = 'http://192.168.0.8:8080';
  // Chrome/웹: 'http://localhost:8080'
  // 실제 기기 테스트 시: 'http://192.168.x.x:8080' (맥 IP)

  static String cardImageUrl(String cardId) => '$baseUrl/images/cards/$cardId.jpg';
  static String tradeImageUrl(String path) => '$baseUrl$path';

  static const String kakaoLogin = '/api/auth/kakao/token';
  static const String cards = '/api/cards';
  static const String prices = '/api/prices/cards';
  static const String assets = '/api/assets';
  static const String gradingAnalyze = '/api/grading/analyze';
  static const String gradingHistory = '/api/grading/history';
  static const String scannerIdentify = '/api/scanner/identify';
}
