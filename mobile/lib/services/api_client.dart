import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

/// like-zzix API 클라이언트. 모든 요청에 앱 플랫폼·버전 헤더를 붙여
/// 서버가 버전 분포를 집계할 수 있게 한다 (Grafana `like-zzix` 대시보드).
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.appVersion,
    http.Client? client,
    String? platform,
  }) : _client = client ?? http.Client(),
       platform = platform ?? (Platform.isIOS ? 'ios' : 'android');

  final String baseUrl;
  final String appVersion;
  final String platform;
  final http.Client _client;

  static const timeout = Duration(seconds: 5);

  Map<String, String> get _headers => {
    'X-App-Platform': platform,
    'X-App-Version': appVersion,
  };

  /// 프리셋 목록 원문(JSON 문자열). 실패 시 null.
  Future<String?> fetchPresets() async {
    final res = await _client
        .get(Uri.parse('$baseUrl/v1/presets'), headers: _headers)
        .timeout(timeout);
    return res.statusCode == 200 ? utf8.decode(res.bodyBytes) : null;
  }

  /// 이벤트 묶음 전송. 서버가 받았으면 true.
  Future<bool> sendEvents(List<Map<String, Object>> events) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/events'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'events': events}),
        )
        .timeout(timeout);
    return res.statusCode == 202;
  }

  void close() => _client.close();
}
