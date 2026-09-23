import 'dart:io';

import 'package:flutter/material.dart';

import 'package:unustasis/service/scooter_artwork_cache.dart';

typedef ScooterArtworkLoader = Future<File?> Function({
  required ScooterArtworkView view,
  required String color,
  required bool matte,
});

class RenderedScooterArtwork extends StatefulWidget {
  const RenderedScooterArtwork({
    super.key,
    required this.view,
    required this.color,
    required this.matte,
    required this.fallbackAsset,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.loader,
  });

  final ScooterArtworkView view;
  final String color;
  final bool matte;
  final String fallbackAsset;
  final double? height;
  final double? width;
  final BoxFit fit;
  final int? cacheWidth;
  final ScooterArtworkLoader? loader;

  @override
  State<RenderedScooterArtwork> createState() => _RenderedScooterArtworkState();
}

class _RenderedScooterArtworkState extends State<RenderedScooterArtwork> {
  late Future<File?> _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RenderedScooterArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.view != oldWidget.view ||
        widget.color != oldWidget.color ||
        widget.matte != oldWidget.matte ||
        widget.loader != oldWidget.loader) {
      _load();
    }
  }

  void _load() {
    final loader = widget.loader ?? ScooterArtworkCache.instance.get;
    _file = loader(
      view: widget.view,
      color: widget.color,
      matte: widget.matte,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return _fallback();
        return Image.file(
          file,
          key: ValueKey('rendered-scooter-${widget.view.name}-${widget.color}-${widget.matte}'),
          height: widget.height,
          width: widget.width,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _fallback(),
        );
      },
    );
  }

  Widget _fallback() => Image.asset(
        widget.fallbackAsset,
        key: ValueKey('rendered-scooter-fallback-${widget.view.name}'),
        height: widget.height,
        width: widget.width,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
      );
}
