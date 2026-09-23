import 'dart:io';

import 'package:flutter/material.dart';
import 'package:unustasis/service/scooter_artwork_cache.dart';

class RenderedScooterArtwork extends StatefulWidget {
  const RenderedScooterArtwork({
    super.key,
    required this.view,
    required this.color,
    required this.matte,
    required this.fallbackAsset,
    this.height,
    this.width,
    this.fit,
    this.cacheWidth,
    this.cache,
  });

  final ScooterArtworkView view;
  final String color;
  final bool matte;
  final String fallbackAsset;
  final double? height;
  final double? width;
  final BoxFit? fit;
  final int? cacheWidth;
  final ScooterArtworkCache? cache;

  @override
  State<RenderedScooterArtwork> createState() => _RenderedScooterArtworkState();
}

class _RenderedScooterArtworkState extends State<RenderedScooterArtwork> {
  late Future<File?> _file;

  @override
  void initState() {
    super.initState();
    _file = _load();
  }

  @override
  void didUpdateWidget(RenderedScooterArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.view != oldWidget.view ||
        widget.color != oldWidget.color ||
        widget.matte != oldWidget.matte ||
        widget.cache != oldWidget.cache) {
      _file = _load();
    }
  }

  Future<File?> _load() async {
    final cache = widget.cache ?? ScooterArtworkCache.shared;
    return cache.get(view: widget.view, color: widget.color, matte: widget.matte);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null) {
          return Image.file(
            file,
            height: widget.height,
            width: widget.width,
            fit: widget.fit,
            cacheWidth: widget.cacheWidth,
            gaplessPlayback: true,
          );
        }
        return Image.asset(
          widget.fallbackAsset,
          height: widget.height,
          width: widget.width,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          gaplessPlayback: true,
        );
      },
    );
  }
}
