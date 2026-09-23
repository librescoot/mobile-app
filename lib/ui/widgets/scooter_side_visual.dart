import 'package:flutter/material.dart';
import 'package:unustasis/ui/widgets/eclipse_backdrop.dart';
import 'package:unustasis/ui/widgets/rendered_scooter_artwork.dart';

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
    this.eclipseBackdrop = false,
    this.showBackdrop = true,
    this.renderedColor,
    this.renderedColorMatte = true,
  });

  final String imagePath;
  final double height;
  final double? backdropDiameter;
  final Color? backdropColor;
  final bool eclipseBackdrop;
  final bool showBackdrop;
  final String? renderedColor;
  final bool renderedColorMatte;

  @override
  Widget build(BuildContext context) {
    final paintBackdrop = showBackdrop && (Theme.of(context).brightness == Brightness.dark || backdropColor != null);
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (paintBackdrop && eclipseBackdrop)
            EclipseBackdrop(diameter: backdropDiameter ?? height * 1.65)
          else if (paintBackdrop)
            Container(
              key: const ValueKey('scooter-side-dark-backdrop'),
              width: backdropDiameter ?? height * 1.65,
              height: backdropDiameter ?? height * 1.65,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: backdropColor ?? const Color(0xFF3E4549),
              ),
            ),
          if (renderedColor == null)
            Image.asset(
              imagePath,
              height: height,
              cacheWidth: (height * _sideArtAspectRatio * MediaQuery.devicePixelRatioOf(context)).ceil(),
            )
          else
            RenderedScooterArtwork(
              view: ScooterArtworkView.side,
              color: renderedColor!,
              matte: renderedColorMatte,
              height: height,
              cacheWidth: (height * _sideArtAspectRatio * MediaQuery.devicePixelRatioOf(context)).ceil(),
            ),
        ],
      ),
    );
  }
}
