import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/config/constants/api_constants.dart';
import 'package:gardnx_app/core/network/api_interceptors.dart';

/// Dio-based HTTP client for communicating with the GardNx backend.
class ApiClient {
  final Dio _dio;

  Dio get dio => _dio;

  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                connectTimeout: ApiConstants.connectTimeout,
                receiveTimeout: ApiConstants.receiveTimeout,
                sendTimeout: ApiConstants.sendTimeout,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    // Auth interceptor attaches Firebase ID token to every request and
    // signs the user out automatically on 401.
    _dio.interceptors.add(AuthInterceptor());
    if (kDebugMode) {
      _dio.interceptors.add(LoggingInterceptor());
    }
  }

  /// Performs a GET request.
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    );
  }

  /// Performs a POST request.
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
  }) {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
  }

  /// Performs a PUT request.
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    CancelToken? cancelToken,
  }) {
    return _dio.put<T>(
      path,
      data: data,
      cancelToken: cancelToken,
    );
  }

  /// Performs a DELETE request.
  Future<Response<T>> delete<T>(
    String path, {
    CancelToken? cancelToken,
  }) {
    return _dio.delete<T>(
      path,
      cancelToken: cancelToken,
    );
  }

  /// Uploads a file using multipart form data with progress tracking.
  Future<Response<T>> uploadFile<T>(
    String path, {
    required File file,
    required String fieldName,
    Map<String, dynamic>? additionalFields,
    void Function(int, int)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(file.path, filename: fileName),
      if (additionalFields != null) ...additionalFields,
    });

    return _dio.post<T>(
      path,
      data: formData,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
      ),
    );
  }
}

/// Provider for the singleton [ApiClient] instance.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});
