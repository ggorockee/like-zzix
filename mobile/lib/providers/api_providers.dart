import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env.dart';

/// Go API 서버 클라이언트. `API_BASE_URL`이 없는 빌드에서는 null.
final dioProvider = Provider<Dio?>((ref) {
  if (!Env.hasApi) return null;
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: Headers.jsonContentType,
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});
