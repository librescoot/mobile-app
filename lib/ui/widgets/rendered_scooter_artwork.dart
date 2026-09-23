import 'package:flutter/material.dart';

enum ScooterArtworkView { front, side }

class RenderedScooterArtwork extends StatelessWidget {
  const RenderedScooterArtwork({
    super.key,
    required this.view,
    required this.color,
    required this.matte,
    this.height,
    this.width,
    this.fit,
    this.cacheWidth,
  });

  final ScooterArtworkView view;
  final String color;
  final bool matte;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final int? cacheWidth;

  String get _prefix => view == ScooterArtworkView.front ? 'custom_front' : 'custom_side';

  Color get _paintColor => Color(0xFF000000 | int.parse(color.substring(1), radix: 16));

  @override
  Widget build(BuildContext context) {
    final imageFit = fit ?? BoxFit.contain;
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          _image('images/scooter/${_prefix}_base.png', imageFit),
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(_paintColor, BlendMode.modulate),
              child: _image('images/scooter/${_prefix}_panels.png', imageFit),
            ),
          ),
          if (matte)
            Positioned.fill(
              key: const ValueKey('custom-paint-matte-layer'),
              child: _image('images/scooter/${_prefix}_matte.png', imageFit),
            )
          else
            Positioned.fill(
              key: const ValueKey('custom-paint-gloss-layer'),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment(-1.2, -0.8),
                  end: Alignment(1.0, 0.9),
                  colors: [
                    Colors.transparent,
                    Color(0x12FFFFFF),
                    Color(0x42FFFFFF),
                    Color(0x0AFFFFFF),
                    Colors.transparent,
                  ],
                  stops: [0, 0.27, 0.43, 0.62, 1],
                ).createShader(bounds),
                child: _image('images/scooter/${_prefix}_panels.png', imageFit),
              ),
            ),
        ],
      ),
    );
  }

  Widget _image(String asset, BoxFit imageFit) {
    return Image.asset(
      asset,
      height: height,
      width: width,
      fit: imageFit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
    );
  }
}
