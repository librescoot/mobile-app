import 'package:flutter/material.dart';

enum ScooterArtworkView { front, side }

class RenderedScooterArtwork extends StatelessWidget {
  const RenderedScooterArtwork({
    super.key,
    required this.view,
    required this.color,
    required this.matte,
    this.showShadow = true,
    this.height,
    this.width,
    this.fit,
    this.cacheWidth,
  });

  final ScooterArtworkView view;
  final String color;
  final bool matte;
  final bool showShadow;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final int? cacheWidth;

  String get _prefix => view == ScooterArtworkView.front ? 'custom_front' : 'custom_side';

  Color get _paintColor => Color(0xFF000000 | int.parse(color.substring(1), radix: 16));

  @override
  Widget build(BuildContext context) {
    final artwork = Stack(
      alignment: Alignment.center,
      children: [
        if (showShadow)
          Positioned.fill(
            key: const ValueKey('scooter-ground-shadow'),
            child: _image('images/scooter/${_prefix}_shadow.png'),
          ),
        _image('images/scooter/${_prefix}_base.png'),
        Positioned.fill(
          key: ValueKey(matte ? 'custom-paint-matte-layer' : 'custom-paint-gloss-layer'),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(_paintColor, BlendMode.modulate),
            child: _image('images/scooter/${_prefix}_${matte ? 'matte' : 'gloss'}.png'),
          ),
        ),
      ],
    );
    final sizedArtwork = height != null && width == null
        ? SizedBox(
            width: height! * (view == ScooterArtworkView.front ? 866 / 1800 : 2110 / 1738),
            height: height,
            child: artwork,
          )
        : artwork;
    return RepaintBoundary(child: sizedArtwork);
  }

  Widget _image(String asset) {
    return Image.asset(
      asset,
      height: height,
      width: width,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
    );
  }
}
