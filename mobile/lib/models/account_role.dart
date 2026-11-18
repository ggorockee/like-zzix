/// 앱 사용자 역할. 로그인하지 않은 사용자는 [guest].
enum AccountRole {
  guest,
  user,
  staff,
  superuser;

  /// 서버 사용자 플래그(`is_staff`, `is_superuser`) → 역할. superuser가 우선.
  factory AccountRole.fromFlags({
    required bool isStaff,
    required bool isSuperuser,
  }) => isSuperuser
      ? superuser
      : isStaff
      ? staff
      : user;

  /// 광고 면제 역할 (스태프·슈퍼계정).
  bool get isAdFree => this == staff || this == superuser;
}
