import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unustasis/service/scooter_artwork_cache.dart';

void main() {
  const png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

  test('builds the immutable Sunshine artwork URL', () {
    expect(
      ScooterArtworkCache.artworkUri(
        view: ScooterArtworkView.front,
        color: '#D5d5D5',
        matte: true,
      ).toString(),
      'https://sunshine.rescoot.org/cached/scooter/front_recolored_d5d5d5_matte_500x1040.png',
    );
    expect(
      ScooterArtworkCache.artworkUri(
        view: ScooterArtworkView.side,
        color: '0F214F',
        matte: false,
      ).toString(),
      'https://sunshine.rescoot.org/cached/scooter/side_recolored_0f214f_800x660.png',
    );
  });

  test('downloads once and reuses the durable local file', () async {
    final directory = await Directory.systemTemp.createTemp('scooter-artwork-test-');
    addTearDown(() => directory.delete(recursive: true));
    var requests = 0;
    final cache = ScooterArtworkCache(
      client: MockClient((request) async {
        requests++;
        return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
      }),
      directory: () async => directory,
    );

    final first = await cache.get(
      view: ScooterArtworkView.side,
      color: '#123ABC',
      matte: true,
    );
    final second = await cache.get(
      view: ScooterArtworkView.side,
      color: '#123ABC',
      matte: true,
    );

    expect(first, isNotNull);
    expect(second!.path, first!.path);
    expect(await first.readAsBytes(), png);
    expect(requests, 1);
  });

  test('returns null without caching invalid responses', () async {
    final directory = await Directory.systemTemp.createTemp('scooter-artwork-test-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = ScooterArtworkCache(
      client: MockClient((request) async => http.Response('not an image', 200)),
      directory: () async => directory,
    );

    expect(
      await cache.get(view: ScooterArtworkView.front, color: '#ABCDEF', matte: false),
      isNull,
    );
    expect(directory.listSync(), isEmpty);
  });

  test('rejects malformed colors before making a request', () {
    expect(
      () => ScooterArtworkCache.artworkUri(
        view: ScooterArtworkView.front,
        color: 'blue',
        matte: true,
      ),
      throwsArgumentError,
    );
  });
}
