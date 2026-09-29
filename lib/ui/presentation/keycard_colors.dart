import 'package:flutter/material.dart';

const keycardColors = <Color>[
  Color(0xFFFF554C),
  Color(0xFF0395FF),
  Color(0xFF245544),
  Color(0xFF303030),
  Color(0xFFFF7043),
  Color(0xFF009688),
  Color(0xFF7E57C2),
  Color(0xFFE76F9A),
  Color(0xFF435A98),
  Color(0xFFFFD54F),
  Color(0xFFF6F4EF),
  Color(0xFF6F4D45),
];

Color keycardInkColor(Color color) {
  final darkest = Color.lerp(color, Colors.black, 0.08)!;
  return darkest.computeLuminance() > 0.179 ? Colors.black : Colors.white;
}
