import 'package:flutter/material.dart';

const eclipseBackdropGradient = RadialGradient(
  colors: [
    Color(0xFF426775),
    Color(0xFF304E5D),
    Color(0xFF142A34),
    Color(0xFFD5FBFF),
    Color(0xFF69D8E5),
    Color(0x0069D8E5),
  ],
  stops: [0, 0.52, 0.64, 0.69, 0.76, 1],
);

BoxDecoration eclipseBackdropDecoration() => const BoxDecoration(
      shape: BoxShape.circle,
      gradient: eclipseBackdropGradient,
    );

class EclipseBackdrop extends StatelessWidget {
  const EclipseBackdrop({super.key, required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('eclipse-backdrop'),
        width: diameter,
        height: diameter,
        decoration: eclipseBackdropDecoration(),
      );
}
