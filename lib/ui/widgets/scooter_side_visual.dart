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
    this.backdropImagePath,
    this.backdropImageHeight,
    this.backdropImageOpacity = 1,
  });

  final String imagePath;
  final double height;
  final double? backdropDiameter;
  final String? backdropImagePath;
  final double? backdropImageHeight;
  final double backdropImageOpacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (Theme.of(context).brightness == Brightness.dark)
            if (backdropImagePath != null)
              Opacity(
                opacity: backdropImageOpacity,
                child: Image.asset(
                  backdropImagePath!,
                  key: const ValueKey('scooter-side-dark-image-backdrop'),
                  height: backdropImageHeight ?? backdropDiameter ?? height * 1.65,
                  cacheHeight: ((backdropImageHeight ?? backdropDiameter ?? height * 1.65) *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                ),
              )
            else
              Container(
                key: const ValueKey('scooter-side-dark-backdrop'),
                width: backdropDiameter ?? height * 1.65,
                height: backdropDiameter ?? height * 1.65,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF303437),
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
