import 'package:flutter/foundation.dart';

import 'account_role.dart';
import 'sns_provider.dart';

/// 서버 `GET /v1/auth/me` 응답의 사용자 정보.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.provider,
    required this.isStaff,
    required this.isSuperuser,
    this.email,
    this.name,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'].toString(),
    provider: SnsProvider.tryParse(json['login_method'] as String?),
    email: json['email'] as String?,
    name: json['name'] as String?,
    // 값이 없거나 형식이 다르면 권한을 주지 않는다.
    isStaff: json['is_staff'] == true,
    isSuperuser: json['is_superuser'] == true,
  );

  final String id;
  final SnsProvider? provider;
  final String? email;
  final String? name;
  final bool isStaff;
  final bool isSuperuser;

  AccountRole get role =>
      AccountRole.fromFlags(isStaff: isStaff, isSuperuser: isSuperuser);

  String get displayName => name ?? email ?? '사용자';

  Map<String, dynamic> toJson() => {
    'id': id,
    'login_method': provider?.name,
    'email': email,
    'name': name,
    'is_staff': isStaff,
    'is_superuser': isSuperuser,
  };

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.provider == provider &&
      other.email == email &&
      other.name == name &&
      other.isStaff == isStaff &&
      other.isSuperuser == isSuperuser;

  @override
  int get hashCode =>
      Object.hash(id, provider, email, name, isStaff, isSuperuser);
}
