import 'dart:io';
import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../storage/token_storage.dart';

class ApiClient {
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
    ));

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async {
    final res = await _dio.post(path, data: data);
    return res.data;
  }

  static Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    final res = await _dio.get(path, queryParameters: params);
    return res.data;
  }

  static Future<Map<String, dynamic>> put(String path, Map<String, dynamic> data) async {
    final res = await _dio.put(path, data: data);
    return res.data;
  }

  static Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? params}) async {
    final res = await _dio.patch(path, queryParameters: params);
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
  }) async {
    final formData = FormData();
    fields.forEach((k, v) => formData.fields.add(MapEntry(k, v)));
    for (final entry in files.entries) {
      formData.files.add(MapEntry(
        entry.key,
        await MultipartFile.fromFile(entry.value.path, filename: entry.key),
      ));
    }
    final res = await _dio.post(path, data: formData);
    return res.data;
  }
}
