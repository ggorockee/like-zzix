import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:likezzix/services/api_client.dart';
import 'package:likezzix/services/telemetry_service.dart';

void main() {
  late List<http.Request> requests;
  late int status;

  TelemetryService create() {
    final client = MockClient((req) async {
      requests.add(req);
      return http.Response('{"accepted":1}', status);
    });
    final api = ApiClient(
      baseUrl: 'https://api.test',
      appVersion: '1.0.0',
      platform: 'android',
      client: client,
    );
    final service = TelemetryService(
      api,
      flushInterval: const Duration(hours: 1),
    );
    addTearDown(service.dispose);
    return service;
  }

  setUp(() {
    requests = [];
    status = 202;
  });

  test('이벤트를 (이름, 프리셋)별로 모아 한 번에 전송, 앱 헤더 포함', () async {
    final service = create();
    service
      ..record(AppEvent.presetSelected, preset: 'look-back')
      ..record(AppEvent.presetSelected, preset: 'look-back')
      ..record(AppEvent.presetSelected, preset: 'side-profile')
      ..record(AppEvent.appOpen);
    await service.flush();

    expect(requests, hasLength(1));
    final req = requests.single;
    expect(req.url.toString(), 'https://api.test/v1/events');
    expect(req.headers['X-App-Platform'], 'android');
    expect(req.headers['X-App-Version'], '1.0.0');
    final events = (jsonDecode(req.body) as Map)['events'] as List;
    expect(
      events,
      containsAll([
        {'name': 'preset_selected', 'count': 2, 'preset': 'look-back'},
        {'name': 'preset_selected', 'count': 1, 'preset': 'side-profile'},
        {'name': 'app_open', 'count': 1},
      ]),
    );
    expect(service.pending, isEmpty);
  });

  test('전송 실패 시 개수를 유지했다가 다음에 함께 전송', () async {
    final service = create();
    status = 503;
    service.record(AppEvent.photoSaved, preset: 'p');
    await service.flush();
    expect(service.pending, {('photo_saved', 'p'): 1});

    status = 202;
    service.record(AppEvent.photoSaved, preset: 'p');
    await service.flush();
    final events = (jsonDecode(requests.last.body) as Map)['events'] as List;
    expect(events.single, {'name': 'photo_saved', 'count': 2, 'preset': 'p'});
  });

  test('보낼 것이 없으면 요청하지 않음', () async {
    await create().flush();
    expect(requests, isEmpty);
  });

  test('이벤트 이름은 서버 허용 목록 형식(snake_case)', () {
    for (final e in AppEvent.values) {
      expect(e.wireName, matches(RegExp(r'^[a-z_]+$')));
    }
  });
}
