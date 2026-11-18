import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_session.dart';

/// 인증 세션을 Keychain / Android Keystore 기반 보안 저장소에 보관.
class AuthSessionStore {
  AuthSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'auth_session';

  final FlutterSecureStorage _storage;

  /// 저장된 세션. 저장소 오류나 손상된 값은 세션 없음으로 처리하고 정리.
  Future<AuthSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      debugPrint('[AuthSession] 세션 읽기 실패, 삭제: $error');
      await _storage.delete(key: _key).catchError((Object _) {});
      return null;
    }
  }

  Future<void> write(AuthSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
