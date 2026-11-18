import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/account_role.dart';
import 'package:likezzix/models/auth_session.dart';
import 'package:likezzix/models/auth_user.dart';
import 'package:likezzix/models/sns_credential.dart';
import 'package:likezzix/models/sns_provider.dart';

void main() {
  group('AccountRole', () {
    test('플래그 → 역할 (superuser 우선)', () {
      expect(
        AccountRole.fromFlags(isStaff: false, isSuperuser: false),
        AccountRole.user,
      );
      expect(
        AccountRole.fromFlags(isStaff: true, isSuperuser: false),
        AccountRole.staff,
      );
      expect(
        AccountRole.fromFlags(isStaff: true, isSuperuser: true),
        AccountRole.superuser,
      );
    });

    test('광고 면제는 staff/superuser만', () {
      expect(AccountRole.values.where((r) => r.isAdFree), [
        AccountRole.staff,
        AccountRole.superuser,
      ]);
    });
  });

  group('AuthUser', () {
    test('권한 필드가 bool true가 아니면 권한 없음 (권한 상승 방지)', () {
      final parsed = AuthUser.fromJson({
        'id': 7,
        'login_method': 'kakao',
        'is_staff': 'true',
        'is_superuser': 1,
      });
      expect(parsed.id, '7');
      expect(parsed.role, AccountRole.user);
    });

    test('알 수 없는 login_method는 null', () {
      final parsed = AuthUser.fromJson({'id': '1', 'login_method': 'naver'});
      expect(parsed.provider, isNull);
    });
  });

  test('AuthSession JSON 왕복 변환', () {
    final session = AuthSession.fromJson({
      'access_token': 'a',
      'refresh_token': 'r',
      'user': {
        'id': '1',
        'login_method': 'apple',
        'email': 'x@privaterelay.appleid.com',
        'is_staff': true,
        'is_superuser': false,
      },
    });
    expect(session.user.provider, SnsProvider.apple);
    expect(AuthSession.fromJson(session.toJson()), session);
  });

  test('SNS 자격 증명 요청 본문', () {
    expect(const GoogleCredential(idToken: 'i').toJson(), {'id_token': 'i'});
    expect(const KakaoCredential(accessToken: 'k').toJson(), {
      'access_token': 'k',
    });
    expect(
      const AppleCredential(
        identityToken: 't',
        authorizationCode: 'c',
        rawNonce: 'n',
        fullName: '홍 길동',
      ).toJson(),
      {
        'identity_token': 't',
        'authorization_code': 'c',
        'nonce': 'n',
        'full_name': '홍 길동',
      },
    );
  });
}
