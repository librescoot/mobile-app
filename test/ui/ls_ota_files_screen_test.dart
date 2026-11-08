import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/ota_protocol.dart';
import 'package:scooter_flutter/update_controller.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/screens/ls_ota_files_screen.dart';

import '../../packages/scooter_flutter/test/update_controller_test.dart' as shared;
import 'ls_ota_screen_test.dart' show ScreenService;
import '../support/inline_asset_bundle.dart';

Widget screen(ScreenService service, List<File> files) =>
    ChangeNotifierProvider<ScooterService>.value(
      value: service,
      child: MaterialApp(
          localizationsDelegates: [
            FlutterI18nDelegate(
                translationLoader: InlineFileTranslationLoader(
                    fallbackFile: 'en',
                    basePath: 'assets/i18n',
                    forcedLocale: const Locale('en'))
                  ..assetBundle = InlineStringBundle())
          ],
          home: LsOtaFilesScreen(pickFiles: () async => files)),
    );

class DisconnectableService extends ScreenService {
  DisconnectableService(super.updateController);
  bool connectedValue = true;
  @override
  bool get connected => connectedValue;
}

void main() {
  testWidgets('picked files are uploaded, kept, and installed on request',
      (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final service = ScreenService(h.controller);
    final mender = File('${h.dir.path}/librescoot-unu-mdb-v2.0.0.mender')
      ..writeAsBytesSync([1, 2, 3, 4]);

    await tester.pumpWidget(screen(service, [mender]));
    await tester.pumpAndSettle();
    expect(find.text('No files selected yet.'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Add files'));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(find.text('librescoot-unu-mdb-v2.0.0.mender'), findsOneWidget);
    expect(find.textContaining('Main board (MDB)'), findsOneWidget);
    expect(find.textContaining('Waiting'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Upload to scooter'));
      await shared.until(() => h.controller.manualUploads.single.status ==
          ManualUploadStatus.staged);
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('On the scooter'), findsOneWidget);
    // Staged only: nothing was installed by the upload.
    expect(h.repo.control.writes.every((w) => w[0] != 0x06), true);
    expect(
        h.repo.control.writes.any((w) => w[0] == OtaProtocol.opStartStaged),
        true);

    h.repo.installPhase = 4;
    await tester.runAsync(() async {
      await tester.tap(find.text('Install Main board (MDB)'));
      await shared.until(() => h.controller.manualUploads.single.status ==
          ManualUploadStatus.applied);
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Installed'), findsWidgets);
    expect(h.repo.control.writes.last.sublist(0, 2),
        [OtaProtocol.opApplyStaged, OtaProtocol.componentMdb]);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });

  testWidgets('a disconnected scooter blocks adding and uploading',
      (tester) async {
    final h = shared.UpdateHarness();
    await tester.runAsync(h.init);
    final service = DisconnectableService(h.controller);
    service.connectedValue = false;

    await tester.pumpWidget(screen(service, const []));
    await tester.pumpAndSettle();
    expect(find.text('Connect to the scooter to upload files.'), findsOneWidget);
    final add = tester.widget<ListTile>(
        find.ancestor(of: find.text('Add files'), matching: find.byType(ListTile)));
    expect(add.enabled, false);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await tester.runAsync(h.close);
  });
}
