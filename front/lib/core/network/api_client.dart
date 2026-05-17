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
        if (kDebugMode) {
          debugPrint('[ApiClient] ${err.requestOptions.method} ${err.requestOptions.path} → ${info.statusCode} ${info.message}');
        }
        _onError?.call(info);
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

  static Future<Map<String, dynamic>> delete(String path) async {
    final res = await _dio.delete(path);
    return res.data;
  }

  static Future<Map<String, dynamic>> uploadFile(String path, String filePath, {String field = 'file'}) async {
    final formData = FormData.fromMap({
      field: await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post(path, data: formData);
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
