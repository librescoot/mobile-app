import 'package:flutter/material.dart';

enum ScooterColorFinish { matte, glossy, special }

class ScooterColor {
  final int value;
  final Color displayColor;
  final String simpleName;
  final ScooterColorFinish finish;

  const ScooterColor({
    required this.value,
    required this.displayColor,
    required this.simpleName,
    required this.finish,
  });
}

const List<int> standardScooterColorValues = [0, 2, 3, 4, 5, 6];

int canonicalScooterColor(int value) => value == 1 ? 3 : value;

const Map<int, ScooterColor> scooterColors = {
  0: ScooterColor(
    value: 0,
    displayColor: Color(0xFF303234),
    simpleName: "black",
    finish: ScooterColorFinish.matte,
  ),
  1: ScooterColor(
    value: 1,
    displayColor: Color(0xFFA4A4A4),
    simpleName: "gray",
    finish: ScooterColorFinish.matte,
  ),
  2: ScooterColor(
    value: 2,
    displayColor: Color(0xFF557064),
    simpleName: "green",
    finish: ScooterColorFinish.matte,
  ),
  3: ScooterColor(
    value: 3,
    displayColor: Color(0xFFA4A4A4),
    simpleName: "gray",
    finish: ScooterColorFinish.matte,
  ),
  4: ScooterColor(
    value: 4,
    displayColor: Color(0xFFE87962),
    simpleName: "orange",
    finish: ScooterColorFinish.matte,
  ),
  5: ScooterColor(
    value: 5,
    displayColor: Color(0xFFD43D27),
    simpleName: "red",
    finish: ScooterColorFinish.glossy,
  ),
  6: ScooterColor(
    value: 6,
    displayColor: Color(0xFF0F214F),
    simpleName: "blue",
    finish: ScooterColorFinish.glossy,
  ),
  7: ScooterColor(
    value: 7,
    displayColor: Color(0xFF45484B),
    simpleName: "eclipse",
    finish: ScooterColorFinish.special,
  ),
  8: ScooterColor(
    value: 8,
    displayColor: Color(0xFF76C9C7),
    simpleName: "idioteque",
    finish: ScooterColorFinish.special,
  ),
  9: ScooterColor(
    value: 9,
    displayColor: Color(0xFF64CBE8),
    simpleName: "hover",
    finish: ScooterColorFinish.special,
  ),
};
