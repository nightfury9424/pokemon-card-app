class ApiConstants {
  // --dart-define=BASE_URL=http://192.168.x.x:8080 으로 오버라이드 가능
  // 기본값: 시뮬레이터 = localhost, 실기기(USB) = 맥 IP 직접 지정
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// 카드 마스터 이미지 CDN base — cards/v1 prefix까지 포함.
  /// prod 기본값 = S3 cards/v1. dart-define으로 dev/CloudFront 오버라이드 가능.
  static const String cardCdnBase = String.fromEnvironment(
    'CARD_CDN_BASE',
    defaultValue:
        'https://pokefolio-beta-assets-759135635310-ap-northeast-2-an.s3.ap-northeast-2.amazonaws.com/cards/v1',
  );

  /// dev에서 로컬 백엔드의 /images/cards/*를 우선 시도할지.
  /// prod-safe default = false. dev 빌드에서 명시:
  ///   flutter run --dart-define=USE_LOCAL_CARD_IMAGES=true
  static const bool useLocalCardImages = bool.fromEnvironment(
    'USE_LOCAL_CARD_IMAGES',
    defaultValue: false,
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
