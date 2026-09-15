import 'package:flutter/material.dart';

/// Side-view scooter art with enough dark contrast for dark scooter colours.
class ScooterSideVisual extends StatelessWidget {
  const ScooterSideVisual({
    super.key,
    required this.imagePath,
    required this.height,
    this.backdropDiameter,
  });

  final String imagePath;
  final double height;
  final double? backdropDiameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (Theme.of(context).brightness == Brightness.dark)
            Container(
              key: const ValueKey('scooter-side-dark-backdrop'),
              width: backdropDiameter ?? height * 1.65,
              height: backdropDiameter ?? height * 1.65,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF303437),
              ),
            ),
          Image.asset(imagePath, height: height),
        ],
      ),
    );
  }
}
