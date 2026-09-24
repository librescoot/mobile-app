import 'package:flutter/material.dart';

import 'package:unustasis/ui/theme/scooter_colors.dart';

class ScooterColorSwatch extends StatelessWidget {
  const ScooterColorSwatch({
    super.key,
    required this.scooterColor,
    required this.selected,
    this.size = 64,
  });

  final ScooterColor scooterColor;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = scooterColor.displayColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
          width: selected ? 3 : 1,
        ),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              key: ValueKey('scooter-color-fill-${scooterColor.value}'),
              decoration: BoxDecoration(gradient: _baseGradient(color)),
            ),
            if (scooterColor.finish == ScooterColorFinish.glossy)
              DecoratedBox(
                key: ValueKey('scooter-color-gloss-${scooterColor.value}'),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.65, -0.75),
                    radius: 0.62,
                    stops: const [0, 0.28, 0.62, 1],
                    colors: [
                      Colors.white.withValues(alpha: 0.28),
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            if (scooterColor.finish == ScooterColorFinish.matte)
              CustomPaint(
                key: ValueKey('scooter-color-noise-${scooterColor.value}'),
                painter: _MatteNoisePainter(),
              ),
            if (selected)
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Gradient _baseGradient(Color color) {
    switch (scooterColor.finish) {
      case ScooterColorFinish.matte:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.06)!, color, Color.lerp(color, Colors.black, 0.08)!],
        );
      case ScooterColorFinish.glossy:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.48, 1],
          colors: [
            Color.lerp(color, Colors.white, 0.05)!,
            color,
            Color.lerp(color, Colors.black, 0.2)!,
          ],
        );
      case ScooterColorFinish.special:
        return RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: [Color.lerp(color, Colors.white, 0.48)!, color, Color.lerp(color, Colors.black, 0.42)!],
        );
    }
  }
}

class _MatteNoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var seed = 0x5EED;
    final light = Paint()..color = Colors.white.withValues(alpha: 0.075);
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.055);
    for (var index = 0; index < 150; index++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final x = (seed / 0x7fffffff) * size.width;
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final y = (seed / 0x7fffffff) * size.height;
      canvas.drawCircle(Offset(x, y), index.isEven ? 0.7 : 0.5, index.isEven ? light : dark);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
