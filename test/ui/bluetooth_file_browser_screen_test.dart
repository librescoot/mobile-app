import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/file_transfer_protocol.dart';
import 'package:scooter_flutter/file_transfer_controller.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/bluetooth_file_browser_screen.dart';

import '../support/inline_asset_bundle.dart';

class _BrowserController extends FileTransferController {
  _BrowserController({bool admin = true, this.totalEntries = 5000})
      : admin = admin,
        super(
          cacheDirectory: () async => Directory.systemTemp,
          supportsFirmware: () => true,
          supportsDataBrowser: () => admin,
        );

  final bool admin;
  final int totalEntries;
  bool connected = true;
  Object _scope = Object();
  Object? activeOwner;
  Object? lastOwner;
  Object? externalOwner;
  int cancelCount = 0, listCalls = 0, dataListCalls = 0;
  int resolveCalls = 0, downloadCalls = 0, uploadCalls = 0;
  Completer<List<RemoteFile>>? firstListGate;
  Completer<({List<int> id, int kind})>? firstResolveGate;
  final List<int> rootId = List<int>.filled(16, 0xa5);
  final List<int> nodeId = List<int>.generate(16, (index) => index);

  @override
  bool get available => connected;
  @override
  Object? get connectionScope => _scope;
  @override
  bool get dataBrowserAvailable => connected && admin;

  void connection(bool isConnected) {
    connected = isConnected;
    _scope = Object();
    notifyListeners();
  }

  Future<T> _owned<T>(Object? owner, Future<T> Function() run) async {
    activeOwner = owner;
    lastOwner = owner;
    try {
      return await run();
    } finally {
      if (identical(activeOwner, owner)) activeOwner = null;
    }
  }

  @override
  Future<List<RemoteFile>> list(int store, {Object? owner}) => _owned(owner, () async {
        listCalls++;
        final gate = firstListGate;
        if (listCalls == 1 && gate != null) return gate.future;
        return [
          RemoteFile(name: 'scooter-$listCalls.tar.gz', size: 7, hash: Uint8List.fromList(List<int>.filled(32, 1)))
        ];
      });

  @override
  Future<List<int>> openDataRoot({Object? owner}) => _owned(owner, () async => rootId);

  @override
  Future<void> closeDataDirectories(List<List<int>> directories, {Object? owner}) => _owned(owner, () async {});

  @override
  Future<FileBrowserDirectoryPage> listDataDirectory(List<int> directory,
          {int cursor = 0, int limit = 64, Object? owner}) =>
      _owned(owner, () async {
        dataListCalls++;
        final end = (cursor + limit).clamp(0, totalEntries);
        final entries = [
          for (var i = cursor; i < end; i++)
            FileBrowserEntry(
              name: i == 0 ? 'target.conf' : 'item-$i.txt',
              kind: 1,
              size: 10,
              modifiedSeconds: 1,
              cursor: i + 1,
            ),
        ];
        return FileBrowserDirectoryPage(
          entries: entries,
          nextCursor: end,
          hasMore: end < totalEntries,
        );
      });

  @override
  Future<({List<int> id, int kind})> resolveDataName(List<int> directory, String name, {Object? owner}) =>
      _owned(owner, () async {
        resolveCalls++;
        if (firstResolveGate case final gate?) return gate.future;
        return (id: nodeId, kind: name == 'folder' ? 2 : 1);
      });

  @override
  Future<RemoteFile> statDataNode(String name, List<int> node, {Object? owner}) =>
      _owned(owner, () async => RemoteFile(name: name, size: 10, hash: Uint8List.fromList(List<int>.filled(32, 2))));

  @override
  Future<File> downloadDataNode(String name, List<int> node, {Object? owner}) => _owned(owner, () async {
        downloadCalls++;
        final file = File('${Directory.systemTemp.path}/browser-${DateTime.now().microsecondsSinceEpoch}-$name');
        await file.writeAsString('verified');
        return file;
      });

  @override
  Future<RemoteFile> uploadDataNode(String name, List<int> node, File source, {RemoteFile? replace, Object? owner}) =>
      _owned(owner, () async {
        uploadCalls++;
        return RemoteFile(name: name, size: await source.length(), hash: Uint8List.fromList(List<int>.filled(32, 3)));
      });

  @override
  void cancelOwnedOperation(Object owner) {
    if (identical(activeOwner, owner)) {
      cancelCount++;
      activeOwner = null;
    }
  }

  void beginUnrelatedOperation() => activeOwner = externalOwner = Object();
}

class _Service extends ChangeNotifier implements ScooterService {
  _Service(this.fileTransfers);
  @override
  final _BrowserController fileTransfers;
  @override
  bool connected = true;
  @override
  String? currentScooterId = 'scooter-a';
  @override
  String? connectingScooterId;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected service access');
}

Future<void> _mount(WidgetTester tester, _BrowserController controller,
    {Future<FilePickerResult?> Function()? pickFile, Future<void> Function(File)? shareFile}) async {
  final service = _Service(controller);
  await tester.pumpWidget(ChangeNotifierProvider<ScooterService>.value(
    value: service,
    child: MaterialApp(
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterI18nDelegate(
          translationLoader: InlineFileTranslationLoader(
            basePath: 'assets/i18n',
            fallbackFile: 'en',
            forcedLocale: const Locale('en'),
          )..assetBundle = InlineStringBundle(),
        ),
      ],
      home: BluetoothFileBrowserScreen(pickFile: pickFile, shareFile: shareFile),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openData(WidgetTester tester) async {
  await tester.tap(find.text('/data'));
  await tester.pumpAndSettle();
  if (find.text('Open /data').evaluate().isNotEmpty) {
    await tester.tap(find.text('Open /data'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('disconnect invalidates pending Logs and reconnect permits a fresh retry', (tester) async {
    final controller = _BrowserController()..firstListGate = Completer<List<RemoteFile>>();
    await _mount(tester, controller);
    await tester.pump();
    expect(controller.listCalls, 1);

    controller.connection(false);
    await tester.pump();
    expect(controller.cancelCount, 1);
    expect(find.text('Connect to a scooter with the Bluetooth file tunnel to browse Logs.'), findsOneWidget);

    controller.connection(true);
    await tester.pumpAndSettle();
    expect(find.text('scooter-2.tar.gz'), findsOneWidget);
    controller.firstListGate!.complete([
      RemoteFile(name: 'old-scooter.tar.gz', size: 1, hash: Uint8List.fromList(List<int>.filled(32, 0))),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('old-scooter.tar.gz'), findsNothing);

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('scooter-3.tar.gz'), findsOneWidget);
  });

  testWidgets('large directories advance in bounded pages beyond the old 4096 cap', (tester) async {
    final controller = _BrowserController(totalEntries: 5000);
    await _mount(tester, controller);
    await _openData(tester);
    expect(find.text('item-1.txt'), findsOneWidget);
    expect(find.text('item-64.txt'), findsNothing);
    for (var page = 1; page <= 64; page++) {
      await tester.tap(find.text('Next page'));
      await tester.pumpAndSettle();
    }
    expect(find.text('item-4096.txt'), findsOneWidget);
    await tester.tap(find.text('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('item-4032.txt'), findsOneWidget);
    expect(controller.dataListCalls, 66);
  });

  testWidgets('replacement confirmation warns that consuming services may be affected', (tester) async {
    final source = File('${Directory.systemTemp.path}/browser-replacement-source.txt');
    final controller = _BrowserController(totalEntries: 1);
    await _mount(tester, controller,
        pickFile: () async => FilePickerResult([
              PlatformFile(name: 'target.conf', size: 8, path: source.path),
            ]));
    await _openData(tester);
    await tester.tap(find.byTooltip('Upload file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Upload file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('affect services that use these files'), findsOneWidget);
    expect(controller.uploadCalls, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.uploadCalls, 0);
  });

  testWidgets('late replacement confirmation after a device switch cannot upload', (tester) async {
    final source = File('${Directory.systemTemp.path}/browser-late-replacement.txt');
    final controller = _BrowserController(totalEntries: 1);
    await _mount(tester, controller,
        pickFile: () async => FilePickerResult([
              PlatformFile(name: 'target.conf', size: 8, path: source.path),
            ]));
    await _openData(tester);
    await tester.tap(find.byTooltip('Upload file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Upload file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('affect services that use these files'), findsOneWidget);
    controller.connection(false);
    await tester.pump();
    controller.connection(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Replace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.uploadCalls, 0);
  });

  testWidgets('late picker after disconnect does not upload and cannot cancel another owner', (tester) async {
    final picked = Completer<FilePickerResult?>();
    final controller = _BrowserController(totalEntries: 1);
    await _mount(tester, controller, pickFile: () => picked.future);
    await _openData(tester);
    controller.beginUnrelatedOperation();
    await tester.tap(find.byTooltip('Upload file'));
    await tester.pump();
    expect(controller.activeOwner, same(controller.externalOwner));

    controller.connection(false);
    await tester.pump();
    expect(controller.cancelCount, 0);
    controller.connection(true);
    await tester.pumpAndSettle();
    picked.complete(null);
    await tester.pumpAndSettle();
    expect(controller.uploadCalls, 0);
    expect(controller.cancelCount, 0);
  });

  testWidgets('late name resolution after device switch is not downloaded or shared', (tester) async {
    final controller = _BrowserController(totalEntries: 1)..firstResolveGate = Completer<({List<int> id, int kind})>();
    var shares = 0;
    await _mount(tester, controller, shareFile: (_) async {
      shares++;
    });
    await _openData(tester);
    await tester.tap(find.byTooltip('Download and share'));
    await tester.pump();
    expect(controller.resolveCalls, 1);
    controller.connection(false);
    await tester.pump();
    controller.connection(true);
    await tester.pumpAndSettle();
    controller.firstResolveGate!.complete((id: controller.nodeId, kind: 1));
    await tester.pumpAndSettle();
    expect(controller.downloadCalls, 0);
    expect(shares, 0);
  });
}
