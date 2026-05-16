import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Dio interceptor that automatically attaches the current Firebase Auth
/// ID token to every outgoing request as a Bearer token.
///
/// If the token has expired, it will be force-refreshed before attaching.
class AuthInterceptor extends Interceptor {
  final FirebaseAuth _firebaseAuth;

  AuthInterceptor({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        // getIdToken returns the cached token if still valid, otherwise
        // refreshes it automatically.
        final token = await user.getIdToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }
    } catch (e) {
      debugPrint('AuthInterceptor: Failed to get ID token: $e');
      // Continue without auth header; the server will return 401 if required.
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // The backend will return 401 if token is expired or invalid.
      // Signing out kicks the user back to login.
      debugPrint('AuthInterceptor: Received 401 from ${err.requestOptions.uri} '
          '— signing out user due to invalid or expired session.');
      _firebaseAuth.signOut();
    }
    handler.next(err);
  }
}

/// Dio interceptor that logs HTTP requests and responses in debug mode.
///
/// Provides concise, readable output compared to Dio's built-in
/// [LogInterceptor], focusing on method, URL, status code, and timing.
class LoggingInterceptor extends Interceptor {
  final Map<String, DateTime> _requestTimestamps = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      final key = '${options.method} ${options.uri}';
      _requestTimestamps[key] = DateTime.now();

      debugPrint('');
      debugPrint('--- HTTP REQUEST --->');
      debugPrint('${options.method} ${options.uri}');

      if (options.headers.isNotEmpty) {
        final safeHeaders = Map<String, dynamic>.from(options.headers);
        // Mask the Authorization header to avoid leaking tokens in logs.
        if (safeHeaders.containsKey('Authorization')) {
          final auth = safeHeaders['Authorization'] as String?;
          if (auth != null && auth.length > 20) {
            safeHeaders['Authorization'] =
                '${auth.substring(0, 15)}...[REDACTED]';
          }
        }
        debugPrint('Headers: $safeHeaders');
      }

      if (options.queryParameters.isNotEmpty) {
        debugPrint('Query: ${options.queryParameters}');
      }

      if (options.data != null && options.data is! FormData) {
        debugPrint('Body: ${options.data}');
      }
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final key =
          '${response.requestOptions.method} ${response.requestOptions.uri}';
      final startTime = _requestTimestamps.remove(key);
      final duration = startTime != null
          ? DateTime.now().difference(startTime).inMilliseconds
          : -1;

      debugPrint('');
      debugPrint('<--- HTTP RESPONSE ---');
      debugPrint('${response.statusCode} $key');
      debugPrint('Duration: ${duration}ms');

      if (response.data != null) {
        final dataStr = response.data.toString();
        if (dataStr.length > 500) {
          debugPrint('Body: ${dataStr.substring(0, 500)}...[TRUNCATED]');
        } else {
          debugPrint('Body: $dataStr');
        }
      }
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final key =
          '${err.requestOptions.method} ${err.requestOptions.uri}';
      _requestTimestamps.remove(key);

      debugPrint('');
      debugPrint('<--- HTTP ERROR ---');
      debugPrint('${err.response?.statusCode ?? 'N/A'} $key');
      debugPrint('Type: ${err.type}');
      debugPrint('Message: ${err.message}');

      if (err.response?.data != null) {
        debugPrint('Error Body: ${err.response?.data}');
      }
    }

    handler.next(err);
  }
}
