import 'package:flutter/material.dart';

const keycardIconIds = <String>[
  'contactless',
  'flame',
  'scooter',
  'bolt',
  'star',
  'heart',
];

Widget keycardIcon(String id, {double size = 40}) {
  if (id == 'flame') {
    return Image.asset('assets/icons/librescoot-flame.png', width: size, height: size);
  }
  final icon = switch (id) {
    'scooter' => Icons.two_wheeler,
    'bolt' => Icons.bolt_outlined,
    'star' => Icons.star_outline,
    'heart' => Icons.favorite_outline,
    _ => Icons.contactless_outlined,
  };
  return Icon(icon, size: size, color: Colors.white);
}
