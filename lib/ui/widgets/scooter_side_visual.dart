import 'package:flutter/material.dart';

/// Side-view scooter art with enough dark contrast for dark scooter colours.
///
/// The art is 2110x1738, so a box [height] tall paints it a little wider than
/// [height]. Decoding the source at full resolution costs 14 MB per card,
/// against a 100 MB image cache the whole app shares, so the decode is pinned
/// to the painted width instead.
const double _sideArtAspectRatio = 2110 / 1738;

class ScooterSideVisual extends StatelessWidget {
  const ScooterSideVisual({
    super.key,
    required this.imagePath,
    required this.height,
    this.backdropDiameter,
    this.backdropColor,
    this.backdropBorderColor,
    this.backdropBorderWidth = 1.5,
  });

  final String imagePath;
  final double height;
  final double? backdropDiameter;
  final Color? backdropColor;
  final Color? backdropBorderColor;
  final double backdropBorderWidth;

  @override
  Widget build(BuildContext context) {
    final showBackdrop =
        Theme.of(context).brightness == Brightness.dark || backdropColor != null || backdropBorderColor != null;
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (showBackdrop)
            Container(
              key: const ValueKey('scooter-side-dark-backdrop'),
              width: backdropDiameter ?? height * 1.65,
              height: backdropDiameter ?? height * 1.65,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: backdropColor ?? const Color(0xFF303437),
                border: backdropBorderColor == null
                    ? null
                    : Border.all(color: backdropBorderColor!, width: backdropBorderWidth),
              ),
            ),
          Image.asset(
            imagePath,
            height: height,
            cacheWidth: (height * _sideArtAspectRatio * MediaQuery.devicePixelRatioOf(context)).ceil(),
          ),
        ],
      ),
    );
  }
}
