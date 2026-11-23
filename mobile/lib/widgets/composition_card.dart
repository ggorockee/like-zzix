import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/composition.dart';
import '../models/composition_fit.dart';
import '../models/preset.dart';
import 'composition_painter.dart';
import 'reference_image.dart';

/// 구도 카드: [왼쪽 선·점 도식 | 오른쪽 예시]. 용어를 몰라도 그림만 보고 고를 수 있다.
class CompositionCard extends StatelessWidget {
  const CompositionCard({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final Preset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.title}, ${preset.tip}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.inkRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppTheme.coral : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _panel(CompositionDiagram(preset: preset))),
                    const SizedBox(width: 6),
                    Expanded(child: _panel(CompositionExample(preset: preset))),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preset.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                preset.tip,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.whiteMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _panel(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.expand(child: child),
  );
}

/// 선·점 도식. 사진 프리셋은 인물 자리만 표시한다.
class CompositionDiagram extends StatelessWidget {
  const CompositionDiagram({super.key, required this.preset});

  final Preset preset;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _DiagramPainter(preset));
}

class _DiagramPainter extends CustomPainter {
  const _DiagramPainter(this.preset);

  final Preset preset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = AppTheme.ink);
    final person = Paint()..color = AppTheme.whiteFaint;
    final template = preset.template;
    final targets = Target.of(preset, size);
    if (template != null) {
      CompositionPainter.people(canvas, size, template, person);
      CompositionPainter.elements(
        canvas,
        size,
        template,
        color: AppTheme.coral,
        width: 1.4,
        labels: false,
      );
    } else {
      for (final t in targets) {
        CompositionPainter.figure(canvas, t.box, person);
        canvas.drawRect(
          t.box,
          Paint()
            ..color = AppTheme.coral
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }
    final dot = Paint()..color = AppTheme.coral;
    for (final t in targets) {
      canvas.drawCircle(
        switch (t) {
          FaceTarget() => t.center,
          BodyTarget() => t.head + Offset(0, t.size * 0.07),
        },
        3.2,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_DiagramPainter old) => old.preset != preset;
}

/// 예시: 사진이 있으면 사진, 없으면 구도 데이터로 그린 일러스트.
class CompositionExample extends StatelessWidget {
  const CompositionExample({super.key, required this.preset});

  final Preset preset;

  @override
  Widget build(BuildContext context) {
    final template = preset.template;
    if (template == null) return ReferenceImage(preset: preset);
    final scene = CustomPaint(
      size: Size.infinite,
      painter: _ScenePainter(template),
    );
    final example = template.example;
    if (example == null) return scene;
    return Image.asset(
      example,
      fit: BoxFit.cover,
      cacheWidth: 300,
      errorBuilder: (_, _, _) => scene,
    );
  }
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter(this.template);

  final CompositionTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint fill(Color c, double a) => Paint()..color = c.withValues(alpha: a);
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, fill(AppTheme.white, 0.86));
    final line = Paint()
      ..color = AppTheme.ink.withValues(alpha: 0.35)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    switch (template.scene) {
      case 'hill':
        canvas
          ..drawCircle(
            Offset(w * 0.75, h * 0.22),
            w * 0.1,
            fill(AppTheme.amber, 1),
          )
          ..drawPath(
            Path()
              ..moveTo(w * 0.35, h * 0.5)
              ..lineTo(w * 0.68, h * 0.32)
              ..lineTo(w, h * 0.5)
              ..close(),
            fill(AppTheme.mint, 0.5),
          )
          ..drawRect(Rect.fromLTRB(0, h * 0.5, w, h), fill(AppTheme.mint, 0.3));
      case 'table':
        canvas
          ..drawRect(
            Rect.fromLTRB(0, h * 0.667, w, h),
            fill(AppTheme.amber, 0.45),
          )
          ..drawOval(
            Rect.fromCenter(
              center: Offset(w * 0.38, h * 0.83),
              width: w * 0.3,
              height: h * 0.1,
            ),
            fill(AppTheme.white, 1),
          )
          ..drawRect(
            Rect.fromLTWH(w * 0.64, h * 0.72, w * 0.14, h * 0.15),
            fill(AppTheme.coral, 0.5),
          );
      case 'door':
        canvas
          ..drawRect(Offset.zero & size, fill(AppTheme.ink, 0.5))
          ..drawRect(
            Rect.fromLTRB(w * 0.15, h * 0.1, w * 0.85, h * 0.9),
            fill(AppTheme.white, 0.95),
          );
      case 'corridor':
        canvas.drawRect(
          Rect.fromLTRB(w * 0.3, h * 0.26, w * 0.7, h * 0.82),
          fill(AppTheme.amber, 0.35),
        );
        for (final (a, b) in const [
          (Offset(0, 0), Offset(0.3, 0.26)),
          (Offset(1, 0), Offset(0.7, 0.26)),
          (Offset(0, 1), Offset(0.3, 0.82)),
          (Offset(1, 1), Offset(0.7, 0.82)),
        ]) {
          canvas.drawLine(a.scale(w, h), b.scale(w, h), line);
        }
      case 'floor':
        canvas.drawRect(
          Rect.fromLTRB(0, h * 0.6, w, h),
          fill(AppTheme.ink, 0.14),
        );
      case 'wall':
        canvas.drawRect(
          Rect.fromLTRB(0, h * 0.9, w, h),
          fill(AppTheme.ink, 0.18),
        );
    }
    CompositionPainter.people(
      canvas,
      size,
      template,
      fill(AppTheme.coral, 0.95),
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.template != template;
}
