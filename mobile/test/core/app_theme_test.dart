import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/core/app_theme.dart';

void main() {
  test('색은 app_theme.dart에서만 정의한다 (유채색 3 + 무채색)', () {
    final literal = RegExp(
      r'Color\(0x|Color\.from|Colors\.(?!transparent\b)[a-z]',
    );
    final violations = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('core/app_theme.dart')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (literal.hasMatch(lines[i])) {
          violations.add('${file.path}:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('테마의 강조색은 코랄·민트뿐이고 파생 색조가 없다', () {
    final s = AppTheme.dark.colorScheme;
    for (final c in [s.primary, s.secondary, s.secondaryContainer, s.error]) {
      expect(c, AppTheme.coral);
    }
    expect(s.tertiary, AppTheme.mint);
    expect(s.surface, AppTheme.ink);
  });

  test('코랄·민트 위 ink 글자는 WCAG AA(4.5:1) 이상', () {
    double contrast(Color a, Color b) {
      final l = [a.computeLuminance(), b.computeLuminance()];
      return (l.reduce(math.max) + 0.05) / (l.reduce(math.min) + 0.05);
    }

    expect(contrast(AppTheme.coral, AppTheme.ink), greaterThan(4.5));
    expect(contrast(AppTheme.mint, AppTheme.ink), greaterThan(4.5));
    expect(contrast(AppTheme.amber, AppTheme.ink), greaterThan(4.5));
    expect(contrast(AppTheme.white, AppTheme.ink), greaterThan(4.5));
  });
}
