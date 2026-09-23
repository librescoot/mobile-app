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
                shaderCallback: (bounds) => RadialGradient(
                  center:
                      view == ScooterArtworkView.front ? const Alignment(-0.72, -0.62) : const Alignment(-0.78, -0.48),
                  radius: view == ScooterArtworkView.front ? 0.82 : 0.95,
                  colors: const [
                    Color(0x52FFFFFF),
                    Color(0x26FFFFFF),
                    Color(0x08FFFFFF),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.28, 0.58, 1],
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
