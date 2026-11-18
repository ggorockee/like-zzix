/// 지원하는 SNS 로그인 제공자. `name`은 서버 경로(`/v1/auth/{name}`)와 동일.
enum SnsProvider {
  kakao('카카오'),
  google('Google'),
  apple('Apple');

  const SnsProvider(this.label);

  final String label;

  static SnsProvider? tryParse(String? value) {
    for (final provider in values) {
      if (provider.name == value) return provider;
    }
    return null;
  }
}
