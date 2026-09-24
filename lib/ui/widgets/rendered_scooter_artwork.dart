import 'dart:convert';

import 'package:flutter/material.dart';

const _manifestAsset = 'images/scooter/custom_artwork_layers.json';

enum ScooterArtworkView { front, side }

class RenderedScooterArtwork extends StatefulWidget {
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

  @override
  State<RenderedScooterArtwork> createState() => _RenderedScooterArtworkState();
}

class _RenderedScooterArtworkState extends State<RenderedScooterArtwork> {
  AssetBundle? _bundle;
  Future<_ArtworkManifest>? _manifest;

  Color get _paintColor => Color(0xFF000000 | int.parse(widget.color.substring(1), radix: 16));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (_bundle != bundle) {
      _bundle = bundle;
      _manifest = _ArtworkManifest.load(bundle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizedArtwork = FutureBuilder<_ArtworkManifest>(
      future: _manifest,
      builder: (context, snapshot) {
        final manifest = snapshot.data;
        if (snapshot.hasError) {
          return ErrorWidget(snapshot.error!);
        }
        if (manifest == null) {
          return const SizedBox.expand();
        }
        final data = manifest.views[widget.view.name]!;
        return LayoutBuilder(
          builder: (context, constraints) {
            final logicalWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : constraints.hasBoundedHeight
                    ? constraints.maxHeight * data.width / data.height
                    : data.width.toDouble();
            final decodedWidth = widget.cacheWidth ??
                (logicalWidth * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, data.width);
            Widget canvas = _ArtworkCanvas(
              key: ValueKey('${widget.view.name}-$decodedWidth'),
              bundle: _bundle!,
              data: data,
              color: _paintColor,
              matte: widget.matte,
              showShadow: widget.showShadow,
              fit: widget.fit ?? BoxFit.contain,
              decodedWidth: decodedWidth,
            );
            if (widget.showShadow) {
              canvas = KeyedSubtree(
                key: const ValueKey('scooter-ground-shadow'),
                child: canvas,
              );
            }
            return canvas;
          },
        );
      },
    );
    final aspectRatio = widget.view == ScooterArtworkView.front ? 866 / 1800 : 2110 / 1738;
    final Widget artwork;
    if (widget.height != null && widget.width == null) {
      artwork = SizedBox(
        width: widget.height! * aspectRatio,
        height: widget.height,
        child: sizedArtwork,
      );
    } else if (widget.height == null) {
      artwork = SizedBox(
        width: widget.width,
        child: AspectRatio(aspectRatio: aspectRatio, child: sizedArtwork),
      );
    } else {
      artwork = SizedBox(
        width: widget.width,
        height: widget.height,
        child: sizedArtwork,
      );
    }
    return RepaintBoundary(child: artwork);
  }
}

class _ArtworkCanvas extends StatefulWidget {
  const _ArtworkCanvas({
    super.key,
    required this.bundle,
    required this.data,
    required this.color,
    required this.matte,
    required this.showShadow,
    required this.fit,
    required this.decodedWidth,
  });

  final AssetBundle bundle;
  final _ArtworkViewData data;
  final Color color;
  final bool matte;
  final bool showShadow;
  final BoxFit fit;
  final int decodedWidth;

  @override
  State<_ArtworkCanvas> createState() => _ArtworkCanvasState();
}

class _ArtworkCanvasState extends State<_ArtworkCanvas> {
  final List<_PendingImage> _pending = [];
  Map<String, ImageInfo>? _images;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void didUpdateWidget(_ArtworkCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bundle != oldWidget.bundle ||
        widget.data != oldWidget.data ||
        widget.decodedWidth != oldWidget.decodedWidth) {
      _loadImages();
    }
  }

  void _cancelPending() {
    for (final pending in _pending) {
      pending.stream.removeListener(pending.listener);
    }
    _pending.clear();
  }

  void _disposeImages(Map<String, ImageInfo>? images) {
    for (final info in images?.values ?? const <ImageInfo>[]) {
      info.dispose();
    }
  }

  void _loadImages() {
    _cancelPending();
    final generation = ++_generation;
    final layers = widget.data.allLayers;
    final loaded = <String, ImageInfo>{};
    var remaining = layers.length;
    var failed = false;

    for (final layer in layers) {
      final layerWidth = (widget.decodedWidth * layer.width / widget.data.width).ceil().clamp(1, layer.width);
      final provider = ResizeImage.resizeIfNeeded(
        layerWidth,
        null,
        AssetImage(layer.asset, bundle: widget.bundle),
      );
      final stream = provider.resolve(ImageConfiguration(bundle: widget.bundle));
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          stream.removeListener(listener);
          _pending.removeWhere((pending) => identical(pending.listener, listener));
          if (!mounted || generation != _generation || failed) {
            info.dispose();
            return;
          }
          loaded[layer.asset] = info;
          remaining--;
          if (remaining == 0 && !failed) {
            final previous = _images;
            setState(() => _images = loaded);
            _disposeImages(previous);
          }
        },
        onError: (Object error, StackTrace? stackTrace) {
          stream.removeListener(listener);
          _pending.removeWhere((pending) => identical(pending.listener, listener));
          if (!mounted || generation != _generation) {
            return;
          }
          failed = true;
          _cancelPending();
          _disposeImages(loaded);
          loaded.clear();
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'scooter artwork renderer',
              context: ErrorDescription('while loading ${layer.asset}'),
            ),
          );
        },
      );
      _pending.add(_PendingImage(stream, listener));
      stream.addListener(listener);
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancelPending();
    _disposeImages(_images);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    return CustomPaint(
      key: ValueKey(widget.matte ? 'custom-paint-matte-layer' : 'custom-paint-gloss-layer'),
      painter: images == null
          ? null
          : _ArtworkPainter(
              data: widget.data,
              images: images,
              color: widget.color,
              matte: widget.matte,
              showShadow: widget.showShadow,
              fit: widget.fit,
            ),
      child: const SizedBox.expand(),
    );
  }
}

class _PendingImage {
  const _PendingImage(this.stream, this.listener);

  final ImageStream stream;
  final ImageStreamListener listener;
}

class _ArtworkPainter extends CustomPainter {
  const _ArtworkPainter({
    required this.data,
    required this.images,
    required this.color,
    required this.matte,
    required this.showShadow,
    required this.fit,
  });

  final _ArtworkViewData data;
  final Map<String, ImageInfo> images;
  final Color color;
  final bool matte;
  final bool showShadow;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final sourceSize = Size(data.width.toDouble(), data.height.toDouble());
    final fitted = applyBoxFit(fit, sourceSize, size);
    final destination = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    final scaleX = destination.width / data.width;
    final scaleY = destination.height / data.height;

    canvas.saveLayer(destination, Paint());
    for (final layer in data.layers(matte: matte, showShadow: showShadow)) {
      final image = images[layer.asset]?.image;
      if (image == null) {
        continue;
      }
      final destinationRect = Rect.fromLTWH(
        destination.left + layer.x * scaleX,
        destination.top + layer.y * scaleY,
        layer.width * scaleX,
        layer.height * scaleY,
      );
      final paint = Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..blendMode = layer.blendMode;
      if (layer.paintMask) {
        paint.colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
      }
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        destinationRect,
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtworkPainter oldDelegate) =>
      data != oldDelegate.data ||
      images != oldDelegate.images ||
      color != oldDelegate.color ||
      matte != oldDelegate.matte ||
      showShadow != oldDelegate.showShadow ||
      fit != oldDelegate.fit;
}

class _ArtworkManifest {
  const _ArtworkManifest(this.views);

  static final Expando<Future<_ArtworkManifest>> _cache = Expando();

  final Map<String, _ArtworkViewData> views;

  static Future<_ArtworkManifest> load(AssetBundle bundle) => _cache[bundle] ??= _load(bundle);

  static Future<_ArtworkManifest> _load(AssetBundle bundle) async {
    final json = jsonDecode(await bundle.loadString(_manifestAsset)) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('unsupported scooter artwork manifest');
    }
    final views = json['views'] as Map<String, dynamic>;
    return _ArtworkManifest({
      for (final entry in views.entries) entry.key: _ArtworkViewData.fromJson(entry.value as Map<String, dynamic>),
    });
  }
}

class _ArtworkViewData {
  const _ArtworkViewData({
    required this.width,
    required this.height,
    required this.shadow,
    required this.under,
    required this.paintLayers,
  });

  factory _ArtworkViewData.fromJson(Map<String, dynamic> json) => _ArtworkViewData(
        width: json['width'] as int,
        height: json['height'] as int,
        shadow: _ArtworkLayer.fromJson(json['shadow'] as Map<String, dynamic>),
        under: _ArtworkLayer.fromJson(json['under'] as Map<String, dynamic>),
        paintLayers: [
          for (final value in json['paintLayers'] as List<dynamic>)
            _ArtworkPaintLayer.fromJson(value as Map<String, dynamic>),
        ],
      );

  final int width;
  final int height;
  final _ArtworkLayer shadow;
  final _ArtworkLayer under;
  final List<_ArtworkPaintLayer> paintLayers;

  List<_ArtworkLayer> get allLayers => [
        shadow,
        under,
        for (final paintLayer in paintLayers) ...[
          paintLayer.paint,
          ...paintLayer.effects,
        ],
      ];

  Iterable<_ArtworkLayer> layers({required bool matte, required bool showShadow}) sync* {
    if (showShadow) {
      yield shadow;
    }
    yield under;
    for (final paintLayer in paintLayers) {
      yield paintLayer.paint;
      yield* paintLayer.effects.where((effect) => matte || !effect.matteOnly);
    }
  }
}

class _ArtworkPaintLayer {
  const _ArtworkPaintLayer({required this.paint, required this.effects});

  factory _ArtworkPaintLayer.fromJson(Map<String, dynamic> json) => _ArtworkPaintLayer(
        paint: _ArtworkLayer.fromJson(json['paint'] as Map<String, dynamic>, paintMask: true),
        effects: [
          for (final value in json['effects'] as List<dynamic>) _ArtworkLayer.fromJson(value as Map<String, dynamic>),
        ],
      );

  final _ArtworkLayer paint;
  final List<_ArtworkLayer> effects;
}

class _ArtworkLayer {
  const _ArtworkLayer({
    required this.asset,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.blendMode,
    required this.matteOnly,
    required this.paintMask,
  });

  factory _ArtworkLayer.fromJson(Map<String, dynamic> json, {bool paintMask = false}) => _ArtworkLayer(
        asset: json['asset'] as String,
        x: json['x'] as int,
        y: json['y'] as int,
        width: json['width'] as int,
        height: json['height'] as int,
        blendMode: BlendMode.values.byName((json['blendMode'] as String?) ?? 'srcOver'),
        matteOnly: (json['matteOnly'] as bool?) ?? false,
        paintMask: paintMask,
      );

  final String asset;
  final int x;
  final int y;
  final int width;
  final int height;
  final BlendMode blendMode;
  final bool matteOnly;
  final bool paintMask;
}
