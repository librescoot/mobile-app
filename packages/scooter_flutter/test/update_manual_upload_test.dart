import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/ota_protocol.dart';
import 'package:scooter_flutter/update_controller.dart';

import 'update_controller_test.dart';

void main() {
  late UpdateHarness h;
  setUp(() async {
    h = UpdateHarness();
    await h.init();
  });
  tearDown(() => h.close());

  File artifact(String name) =>
      File('${h.dir.path}/$name')..writeAsBytesSync([1, 2, 3, 4]);

  test('artifacts are staged one after another and applied per board',
      () async {
    h.controller.addManualUploads([
      artifact('librescoot-unu-mdb-v2.0.0.mender'),
      artifact('librescoot-unu-dbc-v2.0.0.hdelta'),
    ]);
    expect(h.controller.manualUploads.map((u) => u.component),
        [OtaProtocol.componentMdb, OtaProtocol.componentDbc]);
    expect(h.controller.manualUploads.first.bundleId,
        'librescoot-unu-mdb-v2.0.0');
    // A delta keeps its extension so update-service dispatches on it.
    expect(h.controller.manualUploads.last.bundleId,
        'librescoot-unu-dbc-v2.0.0.hdelta');

    await h.controller.uploadManualUploads();

    expect(
        h.controller.manualUploads
            .every((u) => u.status == ManualUploadStatus.staged),
        true);
    // Both went out as staged transfers, so nothing was installed.
    final starts = h.repo.control.writes.where((w) => w[0] == 0x02).toList();
    expect(starts.length, 2);
    expect(h.repo.control.writes.where((w) => w[0] == 0x01), isEmpty);
    expect(h.controller.manualHasStaged(OtaProtocol.componentMdb), true);
    expect(h.controller.manualHasStaged(OtaProtocol.componentDbc), true);
    expect(h.controller.transfer.state, OtaTransferState.staged);

    // Applying one board installs that board's artifacts only.
    h.repo.installPhase = 4;
    await h.controller.applyManualUploads(OtaProtocol.componentMdb);
    expect(h.controller.manualUploads.first.status,
        ManualUploadStatus.applied);
    expect(h.controller.manualUploads.last.status, ManualUploadStatus.staged);
    expect(h.repo.control.writes.last.sublist(0, 2),
        [0x06, OtaProtocol.componentMdb]);
    expect(h.controller.manualError, isNull);
  });

  test('a refused apply keeps the artifacts staged for a retry', () async {
    h.controller.addManualUploads([artifact('librescoot-unu-mdb-v2.0.0.delta')]);
    await h.controller.uploadManualUploads();
    expect(h.controller.manualUploads.single.status,
        ManualUploadStatus.staged);

    h.repo.applyError = 'an install is already running';
    await h.controller.applyManualUploads(OtaProtocol.componentMdb);

    expect(h.controller.manualError, isNotNull);
    expect(h.controller.manualUploads.single.status,
        ManualUploadStatus.staged);
    expect(h.controller.manualApplyingComponent, isNull);
    expect(h.controller.busy, false);
  });

  test('a name the scooter cannot accept is reported without sending bytes',
      () async {
    h.controller.addManualUploads([artifact('bad name!.mender')]);
    await h.controller.uploadManualUploads();

    expect(h.controller.manualUploads.single.status, ManualUploadStatus.failed);
    expect(h.controller.manualUploads.single.error, isNotNull);
    expect(h.repo.control.writes, isEmpty);
    expect(h.repo.data.writes, isEmpty);
  });

  test('a missing file fails its entry and the queue continues', () async {
    final first = artifact('librescoot-unu-mdb-v2.0.0.mender');
    h.controller.addManualUploads([first, artifact('librescoot-unu-mdb-v2.1.0.delta')]);
    first.deleteSync();

    await h.controller.uploadManualUploads();

    expect(h.controller.manualUploads.first.status, ManualUploadStatus.failed);
    expect(h.controller.manualUploads.last.status, ManualUploadStatus.staged);
  });

  test('the board can be moved after adding a file with an unclear name',
      () async {
    h.controller.addManualUploads([artifact('my-build.delta')],
        fallbackComponent: OtaProtocol.componentMdb);
    expect(h.controller.manualUploads.single.component,
        OtaProtocol.componentMdb);

    final upload = h.controller.manualUploads.single;
    h.controller.removeManualUpload(upload);
    h.controller.addManualUploads([upload.file],
        fallbackComponent: OtaProtocol.componentDbc);
    expect(h.controller.manualUploads.single.component,
        OtaProtocol.componentDbc);

    await h.controller.uploadManualUploads();
    expect(h.controller.manualHasStaged(OtaProtocol.componentDbc), true);
  });

  test('clearing the queue drops staged artifacts from the list', () async {
    h.controller.addManualUploads([artifact('librescoot-unu-mdb-v2.0.0.mender')]);
    await h.controller.uploadManualUploads();
    h.controller.clearManualUploads();
    expect(h.controller.manualUploads, isEmpty);
    expect(h.controller.manualHasAnyStaged, false);
  });
}
