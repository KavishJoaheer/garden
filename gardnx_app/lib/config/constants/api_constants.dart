import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// API endpoint constants for the GardNx backend.
class ApiConstants {
  ApiConstants._();

  /// Base URL for the GardNx backend API.
  ///
  /// Defaults:
  /// - Android device (LAN): `192.168.100.19`
  /// - iOS simulator: `localhost`
  ///
  /// Override without code changes:
  /// `flutter run --dart-define=BACKEND_HOST=192.168.1.50 --dart-define=BACKEND_PORT=8000`
  static String get baseUrl {
    const scheme =
        String.fromEnvironment('BACKEND_SCHEME', defaultValue: 'http');
    const hostOverride = String.fromEnvironment('BACKEND_HOST', defaultValue: '');
    const port = String.fromEnvironment('BACKEND_PORT', defaultValue: '8000');
    const apiPrefix =
        String.fromEnvironment('BACKEND_API_PREFIX', defaultValue: '/api/v1');

    final host = hostOverride.isNotEmpty ? hostOverride : _defaultHost;
    final normalizedPrefix = apiPrefix.startsWith('/') ? apiPrefix : '/$apiPrefix';

    return '$scheme://$host:$port$normalizedPrefix';
  }

  static String get _defaultHost {
    if (kIsWeb) return 'localhost';
    if (Platform.isAndroid) return '10.0.2.2' ;
    return 'localhost';
  }

  // ---------------------------------------------------------------------------
  // Analysis endpoints
  // ---------------------------------------------------
  // ------------------------
  static const analysisUpload = '/analysis/upload';
  static const analysisSegment = '/analysis/segment';
  static const analysisResult = '/analysis/result';

  // ---------------------------------------------------------------------------
  // Plant catalog endpoints
  // ---------------------------------------------------------------------------
  static const plantsCatalog = '/plants/catalog';
  static const plantsRecommend = '/plants/recommend';

  // ---------------------------------------------------------------------------
  // Layout endpoints
  // ---------------------------------------------------------------------------
  static const layoutGenerate = '/layout/generate';
  static const layoutValidate = '/layout/validate';
  static const layoutSpacing = '/layout/spacing';

  // ---------------------------------------------------------------------------
  // Climate endpoints
  // ---------------------------------------------------------------------------
  static const climateCurrent = '/climate/current';
  static const climateMonthly = '/climate/monthly';

  // ---------------------------------------------------------------------------
  // Calendar / task endpoints
  // ---------------------------------------------------------------------------
  static const calendarGenerate = '/calendar/generate';
  static const calendarTasks = '/calendar/tasks';

  // ---------------------------------------------------------------------------
  // Timeouts
  // ---------------------------------------------------------------------------
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 60);
  static const Duration uploadTimeout = Duration(seconds: 120);
}
