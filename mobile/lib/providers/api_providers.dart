import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env.dart';
import '../services/api_client.dart';
import '../services/telemetry_service.dart';
import 'ad_providers.dart';

/// API 서버 클라이언트. `API_BASE_URL`이 없는 빌드(테스트 등)에서는 null.
final apiClientProvider = Provider<ApiClient?>((ref) {
  if (!Env.hasApi) return null;
  final version = ref.watch(
    appInitProvider.select((s) => s.value?.currentVersion.toString()),
  );
  final client = ApiClient(baseUrl: Env.apiBaseUrl, appVersion: version ?? '');
  ref.onDispose(client.close);
  return client;
});

/// 익명 사용 이벤트 전송. API가 없으면 null (기록하지 않음).
/// 앱이 백그라운드로 갈 때도 즉시 전송한다.
final telemetryProvider = Provider<TelemetryService?>((ref) {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  final service = TelemetryService(api);
  final listener = AppLifecycleListener(
    onHide: () => unawaited(service.flush()),
  );
  ref.onDispose(() {
    listener.dispose();
    service.dispose();
  });
  return service;
});
