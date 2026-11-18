import 'package:flutter/foundation.dart';

/// x.y.z 버전 (빌드 번호·접미사는 무시). 파싱 실패 시 0.0.0.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  factory AppVersion.parse(String value) {
    final core = value.trim().split(RegExp(r'[+\-\s]')).first;
    final parts = core.split('.');
    int at(int i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0;
    return AppVersion(at(0), at(1), at(2));
  }

  static const zero = AppVersion(0, 0, 0);

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

enum UpdateRequirement { none, optional, force }

/// Remote Config에서 읽은 현재 플랫폼의 업데이트 정책.
@immutable
class UpdatePolicy {
  const UpdatePolicy({
    required this.minVersion,
    required this.latestVersion,
    required this.storeUrl,
    this.message = '',
  });

  static const none = UpdatePolicy(
    minVersion: AppVersion.zero,
    latestVersion: AppVersion.zero,
    storeUrl: '',
  );

  final AppVersion minVersion;
  final AppVersion latestVersion;

  /// 비어 있으면 스토어로 보낼 수 없음
  final String storeUrl;
  final String message;

  UpdateRequirement evaluate(AppVersion current) {
    if (current < minVersion) return UpdateRequirement.force;
    // 스토어 링크가 없으면 선택 업데이트는 안내할 방법이 없으므로 띄우지 않는다.
    if (current < latestVersion && storeUrl.isNotEmpty) {
      return UpdateRequirement.optional;
    }
    return UpdateRequirement.none;
  }
}
