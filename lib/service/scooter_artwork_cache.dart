import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const String _artworkBaseUrl = 'https://sunshine.rescoot.org/cached/scooter';

enum ScooterArtworkView {
  front('front', 500, 1040),
  side('side', 800, 660);

  const ScooterArtworkView(this.pathName, this.width, this.height);

  final String pathName;
  final int width;
  final int height;
}

class ScooterArtworkCache {
  ScooterArtworkCache({
    http.Client? client,
    Future<Directory> Function()? directory,
  })  : _client = client ?? http.Client(),
        _directory = directory ?? _defaultDirectory;

  static final ScooterArtworkCache instance = ScooterArtworkCache();

  final http.Client _client;
  final Future<Directory> Function() _directory;
  final Map<String, Future<File?>> _pending = {};

  static Future<Directory> _defaultDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/custom-scooter-art/v1');
  }

  static String normalizeColor(String color) {
    final value = color.startsWith('#') ? color.substring(1) : color;
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw ArgumentError.value(color, 'color', 'Expected #RRGGBB');
    }
    return value.toLowerCase();
  }

  static Uri artworkUri({
    required ScooterArtworkView view,
    required String color,
    required bool matte,
  }) {
    final hex = normalizeColor(color);
    final finish = matte ? '_matte' : '';
    return Uri.parse(
      '$_artworkBaseUrl/${view.pathName}_recolored_$hex${finish}_${view.width}x${view.height}.png',
    );
  }

  Future<File?> get({
    required ScooterArtworkView view,
    required String color,
    required bool matte,
  }) {
    final hex = normalizeColor(color);
    final finish = matte ? '_matte' : '';
    final key = '${view.pathName}_$hex$finish';
    return _pending.putIfAbsent(
      key,
      () => _load(view: view, color: hex, matte: matte).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<File?> _load({
    required ScooterArtworkView view,
    required String color,
    required bool matte,
  }) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final finish = matte ? '_matte' : '';
    final file = File('${directory.path}/${view.pathName}_$color$finish.png');
    if (await _isPng(file)) return file;

    try {
      final response =
          await _client.get(artworkUri(view: view, color: color, matte: matte)).timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok || !_hasPngSignature(response.bodyBytes)) return null;
      final temporary = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await temporary.rename(file.path);
      return file;
    } on Exception {
      return null;
    }
  }

  Future<bool> _isPng(File file) async {
    if (!await file.exists()) return false;
    try {
      return _hasPngSignature(await file.openRead(0, 8).fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk)));
    } on FileSystemException {
      return false;
    }
  }

  static bool _hasPngSignature(List<int> bytes) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }
}
