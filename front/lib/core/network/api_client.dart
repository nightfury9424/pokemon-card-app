import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import '../storage/token_storage.dart';

/// 전역 에러 핸들러 — 화면 단의 BuildContext와 분리해두기 위해 콜백 패턴.
/// MaterialApp.builder 등에서 setApiErrorHandler(...) 한 번 주입하면
/// 401/5xx/네트워크 끊김 시 자동으로 호출됨. (REFACTOR_2026-05-12.md 3차-A)
typedef ApiErrorHandler = void Function(ApiErrorInfo info);

class ApiErrorInfo {
  final int? statusCode;
  final String message;
  final bool isAuthError;   // 401 → 로그인 만료
  final bool isServerError; // 5xx
  final bool isNetworkError;
  ApiErrorInfo({
    this.statusCode,
    required this.message,
    this.isAuthError = false,
    this.isServerError = false,
    this.isNetworkError = false,
  });
}

class ApiClient {
  static ApiErrorHandler? _onError;
  static void setErrorHandler(ApiErrorHandler? handler) => _onError = handler;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenStorage.get();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (DioException err, handler) {
        final info = _classify(err);
        final path = err.requestOptions.uri.path;
        // 항상 로그 — release에서도 진단 가능 (debugPrint는 release에서 일부 무시)
        debugPrint('[ApiClient] ${err.requestOptions.method} $path → ${info.statusCode} ${info.message}');
        // 이미지 proxy(/api/images/secure/**) fail은 SnackBar 표시 X (AuthImage가 자체 errorBuilder 처리).
        // 그 외엔 main.dart의 setErrorHandler 콜백 발화 (SnackBar).
        if (!path.startsWith('/api/images/secure')) {
          _onError?.call(info);
        }
        handler.next(err);
      },
    ));

  static ApiErrorInfo _classify(DioException err) {
    final status = err.response?.statusCode;
    final isNetwork = err.type == DioExceptionType.connectionTimeout
        || err.type == DioExceptionType.receiveTimeout
        || err.type == DioExceptionType.sendTimeout
        || err.type == DioExceptionType.connectionError;
    if (status == 401) {
      return ApiErrorInfo(statusCode: 401, message: '로그인이 만료되었습니다. 다시 로그인해주세요.', isAuthError: true);
    }
    if (status != null && status >= 500) {
      return ApiErrorInfo(statusCode: status, message: '서버에 일시적 문제가 발생했습니다. 잠시 후 다시 시도해주세요.', isServerError: true);
    }
    if (isNetwork) {
      return ApiErrorInfo(message: '네트워크 연결을 확인해주세요.', isNetworkError: true);
    }
    return ApiErrorInfo(statusCode: status, message: err.message ?? '요청 중 오류가 발생했습니다.');
  }

  /// 인증 헤더 포함 byte 다운로드 — proxy endpoint (/api/images/secure/**) 호출용.
  /// url이 절대 URL(http(s)://...)이면 Dio가 baseUrl 무시.
  /// 인증 토글(API_AUTH_ENFORCED=true) 상태에서 사용자 업로드 이미지 받을 때 필수.
  ///
  /// 실패 시 throw 대신 null 반환 — AuthImage가 errorBuilder로 처리.
  /// 인터셉터의 SnackBar 콜백은 /api/images/secure/** path 제외 (image fail은 조용히).
  static Future<List<int>?> downloadBytes(String url) async {
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      debugPrint('[ApiClient.downloadBytes] ${res.statusCode} bytes=${res.data?.length} url=$url');
      return res.statusCode == 200 ? res.data : null;
    } catch (e) {
      debugPrint('[ApiClient.downloadBytes] FAIL url=$url err=$e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async {
    final res = await _dio.post(path, data: data);
    return res.data;
  }

  static Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    final res = await _dio.get(path, queryParameters: params);
    return res.data;
  }

  /// 응답 본문이 JSON 배열인 엔드포인트 (예: /api/cards/market/top-gainers)
  static Future<List<dynamic>> getList(String path, {Map<String, dynamic>? params}) async {
    final res = await _dio.get<List<dynamic>>(path, queryParameters: params);
    return res.data ?? const [];
  }

  static Future<Map<String, dynamic>> put(String path, Map<String, dynamic> data) async {
    final res = await _dio.put(path, data: data);
    return res.data;
  }

  static Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? params, Map<String, dynamic>? data}) async {
    final res = await _dio.patch(path, queryParameters: params, data: data);
    return res.data;
  }

  /// 2026-05-29 admin Stage 0 — delete body 지원 (HTTP DELETE with optional JSON payload).
  /// 기존 호출처는 path 만 넘기던 단일 시그니처 → data optional 추가 (backward compat).
  static Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? data}) async {
    final res = await _dio.delete(path, data: data);
    return res.data;
  }

  static Future<Map<String, dynamic>> blockUser(String userId) {
    return post('/api/blocks/$userId', {});
  }

  static Future<Map<String, dynamic>> unblockUser(String userId) {
    return delete('/api/blocks/$userId');
  }

  static Future<List<dynamic>> getBlockedUsers() async {
    final res = await get('/api/blocks/me');
    return (res['data'] as List?) ?? const [];
  }

  // Phase 1B: 채팅방 나가기 — 본인 hidden_at set. DB 보존, 본인 list 미노출.
  static Future<Map<String, dynamic>> leaveRoom(String roomId) {
    return post('/api/chat/rooms/$roomId/leave', {});
  }

  // Phase 1B: 채팅방 입력창/안내 상태 ({canSendMessage, blockNotice, blockedByMe,
  // blockedByOther, otherLeft, isExcludedFromActiveTrade}).
  static Future<Map<String, dynamic>> getConversationState(String roomId) {
    return get('/api/chat/rooms/$roomId/conversation-state');
  }

  // 거래중 모델: 판매글에 연결된 채팅 상대 후보 (판매자만, 차단 user 제외).
  static Future<List<dynamic>> getChatPartners(String tradeId) async {
    final res = await get('/api/trades/$tradeId/chat-partners');
    return (res['data'] as List?) ?? const [];
  }

  // MY > 내 판매 내역 — JWT principal 기반 본인 이력 (OPEN/RESERVED/COMPLETED, DELETED 숨김).
  // sellerId 인자 받지 X — IDOR 방지. backend 가 @AuthenticationPrincipal 에서 결정.
  static Future<Map<String, dynamic>> getMyHistory({int page = 0, int size = 20}) {
    return get('/api/trades/me/history', params: {'page': page, 'size': size});
  }

  // 거래중 모델: status 변경 + (RESERVED 시) chatRoomId 지정.
  static Future<Map<String, dynamic>> updateTradeStatus(
      String tradeId, String status, {String? chatRoomId}) {
    final body = <String, dynamic>{'status': status};
    if (chatRoomId != null && chatRoomId.isNotEmpty) {
      body['chatRoomId'] = chatRoomId;
    }
    return patch('/api/trades/$tradeId/status', data: body);
  }

  static Future<Map<String, dynamic>> uploadFile(
    String path,
    String filePath, {
    String field = 'file',
    Duration sendTimeout = const Duration(seconds: 60),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) async {
    // 2026-05-28 Codex 사후 리뷰: 10MB 업로드를 100KB/s 회선에서 send 가 무한 hang 가능.
    // 기본 60s sendTimeout (10MB ÷ 170KB/s ≈ 60s 마진), 30s receiveTimeout.
    final formData = FormData.fromMap({
      field: await MultipartFile.fromFile(filePath),
    });
    final options = Options(
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
    );
    final res = await _dio.post(path, data: formData, options: options);
    return res.data;
  }

  static Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, File> files,
    Map<String, String> fields = const {},
    Duration? sendTimeout,
    Duration? receiveTimeout,
  }) async {
    final formData = FormData();
    fields.forEach((k, v) => formData.fields.add(MapEntry(k, v)));
    for (final entry in files.entries) {
      formData.files.add(MapEntry(
        entry.key,
        await MultipartFile.fromFile(entry.value.path, filename: entry.key),
      ));
    }
    final options = Options(
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
    );
    final res = await _dio.post(path, data: formData, options: options);
    return res.data;
  }

  static Future<Map<String, dynamic>> postBytes(
    String path, {
    required String fieldName,
    required List<int> bytes,
    String filename = 'frame.jpg',
    Duration? receiveTimeout,
  }) async {
    final formData = FormData.fromMap({
      fieldName: MultipartFile.fromBytes(bytes, filename: filename),
    });
    final options = receiveTimeout != null
        ? Options(receiveTimeout: receiveTimeout)
        : null;
    final res = await _dio.post(path, data: formData, options: options);
    return res.data;
  }
}
