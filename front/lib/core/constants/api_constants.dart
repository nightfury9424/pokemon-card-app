import 'package:flutter/foundation.dart';

class ApiConstants {
  // dart-define BASE_URL 우선. 없으면 release=prod, debug=localhost 자동 분기.
  // TestFlight/App Store 빌드는 자동 prod URL — dart-define 누락해도 안전.
  // dev 시 맥 IP 지정: flutter run --dart-define=BASE_URL=http://192.168.x.x:8080
  static const String _override = String.fromEnvironment('BASE_URL');
  static const String _prodBaseUrl = 'https://52.78.3.120.nip.io';
  static const String _devBaseUrl = 'http://localhost:8080';
  static String get baseUrl =>
      _override.isNotEmpty ? _override : (kReleaseMode ? _prodBaseUrl : _devBaseUrl);

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

  /// 고객지원 문의 이메일 — MY → 고객지원 + 모든 cs 진입점에서 사용.
  /// 운영용 도메인 메일(예: support@pokefolio.app) 준비되면 이 상수만 교체.
  static const String supportEmail = 'nightfury9424@gmail.com';
}
