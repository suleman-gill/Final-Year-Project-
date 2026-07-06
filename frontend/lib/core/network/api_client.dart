import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import '../../config/routes.dart';

/// Backend base URL — resolves correctly for Android emulator, iOS, and web.
final String fallbackUrl = 'https://foolish-gecko-100.loca.lt';

final backendBaseUrl = const String.fromEnvironment('API_BASE_URL', defaultValue: '') != ''
    ? const String.fromEnvironment('API_BASE_URL')
    : fallbackUrl;

/// Centralized, singleton Dio instance with the 401 interceptor attached.
///
/// Every HTTP call in the app should use this client so that expired
/// tokens are caught globally and the user is redirected to the Login screen.
final Dio apiClient = _createApiClient();

const _secureStorage = FlutterSecureStorage();

Dio _createApiClient() {
  final dio = Dio(BaseOptions(
    baseUrl: backendBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // ── 401 Interceptor ────────────────────────────────────────────────
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Attach the JWT to every request if available
        final token = await _secureStorage.read(key: 'auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        // Bypass localtunnel landing page
        options.headers['Bypass-Tunnel-Reminder'] = 'true';
        handler.next(options);
      },
      onError: (DioException error, handler) async {
        if (error.response?.statusCode == 401) {
          final path = error.requestOptions.path;
          final isPublicAuth = path.contains('/api/auth/login') ||
              path.contains('/api/auth/register') ||
              path.contains('/api/auth/google') ||
              path.contains('/api/auth/forgot-password') ||
              path.contains('/api/auth/verify-otp') ||
              path.contains('/api/auth/reset-password');

          if (!isPublicAuth) {
            // ── Token expired or invalid ──────────────────────────────
            // 1. Clear the stored JWT
            await _secureStorage.delete(key: 'auth_token');

            // 2. Redirect to login using the global NavigatorKey
            //    This prevents the app from freezing on an expired session.
            if (rootNavigatorKey.currentContext != null) {
              GoRouter.of(rootNavigatorKey.currentContext!).go('/login');
            }
          }
        }
        // Always forward the error so callers can still catch it
        handler.next(error);
      },
    ),
  );

  return dio;
}
