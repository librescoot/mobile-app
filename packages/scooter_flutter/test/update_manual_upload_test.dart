import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/ota_protocol.dart';
import 'package:scooter_core/update_planner.dart';
import 'package:scooter_flutter/update_controller.dart';

import 'update_controller_test.dart';
import 'update_controller_test.dart' as shared;

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
    // The dashboard set is a base image plus two deltas, uploaded in one run:
    // nothing is installed until each board is asked for.
    h.controller.addManualUploads([
      artifact('librescoot-unu-mdb-v2.0.0.mender'),
      artifact('librescoot-unu-mdb-v2.0.1.delta'),
      artifact('librescoot-unu-dbc-v2.0.0.hdelta'),
    ]);
    expect(h.controller.manualUploads.map((u) => u.component), [
      OtaProtocol.componentMdb,
      OtaProtocol.componentMdb,
      OtaProtocol.componentDbc,
    ]);
    // A full image drops the extension, a delta keeps it so update-service
    // dispatches on it.
    expect(h.controller.manualUploads.first.bundleId,
        'librescoot-unu-mdb-v2.0.0');
    expect(h.controller.manualUploads[1].bundleId,
        'librescoot-unu-mdb-v2.0.1.delta');
    expect(h.controller.manualUploads.last.bundleId,
        'librescoot-unu-dbc-v2.0.0.hdelta');

    await h.controller.uploadManualUploads();

    expect(
        h.controller.manualUploads
            .every((u) => u.status == ManualUploadStatus.staged),
        true);
    // All three went out as staged transfers, so nothing was installed.
    final starts = h.repo.control.writes.where((w) => w[0] == 0x02).toList();
    expect(starts.length, 3);
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

    // The dashboard is applied by its own request, so the scooter can hand the
    // staged set to the board that owns it.
    await h.controller.applyManualUploads(OtaProtocol.componentDbc);
    expect(h.repo.control.writes.last.sublist(0, 2),
        [0x06, OtaProtocol.componentDbc]);
    expect(
        h.controller.manualUploads
            .every((u) => u.status == ManualUploadStatus.applied),
        true);
    expect(h.controller.manualHasAnyStaged, false);
  });

  test('the release index fills the queue with the whole delta chain',
      () async {
    // Nobody has to hold the files: the channel index names the hops between
    // the installed version and the newest one, and the app fetches them.
    h.provider.releases = [
      shared.release('v1.2.0'),
      shared.release('v1.1.0'),
      shared.release('v1.0.0', full: true),
    ];
    await h.controller.refresh();
    expect(h.controller.plan, isNotNull);

    await h.controller.loadUpdateChain();

    expect(h.controller.manualError, isNull);
    // The test index carries main-board artifacts only, so the dashboard chain
    // is empty and no DBC file is fetched.
    expect(h.controller.manualUploads.map((u) => u.name), [
      'librescoot-unu-mdb-v1.1.0.delta',
      'librescoot-unu-mdb-v1.2.0.delta',
    ]);
    expect(
        h.controller.manualUploads
            .every((u) => u.bundleId == u.name),
        true);
    // Downloaded, not uploaded yet.
    expect(h.repo.control.writes.where((w) => w[0] == 0x02), isEmpty);
    expect(h.provider.urls.length, 2);

    await h.controller.uploadManualUploads();
    expect(
        h.controller.manualUploads
            .every((u) => u.status == ManualUploadStatus.staged),
        true);

    // Both MDB hops go out as one staged set and are installed by one request,
    // so the scooter resolves the chain and reboots once.
    h.repo.installPhase = 4;
    await h.controller.applyManualUploads(OtaProtocol.componentMdb);
    expect(h.repo.control.writes.last.sublist(0, 2),
        [0x06, OtaProtocol.componentMdb]);
    expect(
        h.controller.manualUploads
            .every((u) => u.status == ManualUploadStatus.applied),
        true);
  });

  test('the latest installed version is reported as up to date', () async {
    const latest = 'nightly-20261109T110233';
    h.repo.version = latest;
    h.provider.releases = [
      FirmwareRelease.fromJson({
        'tag_name': latest,
        'prerelease': true,
        'assets': [
          for (final variant in ['unu-mdb', 'unu-dbc'])
            for (final ext in ['delta', 'mender'])
              {
                'name': 'librescoot-$variant-$latest.$ext',
                'url': 'https://dl/$latest/$variant.$ext',
                'size': 30,
              },
        ],
      }),
    ];
    await h.controller.refresh();

    await h.controller.loadUpdateChain();

    expect(h.controller.manualUploads, isEmpty);
    expect(h.controller.manualError, isNull);
    expect(h.controller.manualInfo, 'ls_ota_files_up_to_date');
    expect(h.provider.urls, isEmpty);
  });

  test('a chain is not offered when the installed version is not in the index',
      () async {
    h.provider.releases = [shared.release('v2.0.0')];
    await h.controller.refresh();

    await h.controller.loadUpdateChain();

    expect(h.controller.manualUploads, isEmpty);
    expect(h.controller.manualError, isNotNull);
    expect(h.provider.urls, isEmpty);
  });

  test('older software installs each file right away and stops the queue',
      () async {
    // Without the staged-upload capability the scooter answers a staging
    // request with nothing at all, so the queue has to use the transfer that
    // exists there. That install ends in a pending reboot, and a second file
    // cannot apply on top of an image that has not been booted.
    h.stagedSupported = false;
    h.repo.installPhase = 4; // PhaseSuccess
    h.controller.addManualUploads([
      artifact('librescoot-unu-mdb-v2.0.0.mender'),
      artifact('librescoot-unu-mdb-v2.0.1.delta'),
    ]);

    await h.controller.uploadManualUploads();

    expect(h.controller.manualUploads.first.status,
        ManualUploadStatus.applied);
    expect(h.controller.manualUploads.last.status,
        ManualUploadStatus.pending);
    expect(h.controller.manualQueueHalted, true);
    // START, not START_STAGED: nothing was left on the scooter for later.
    expect(h.repo.control.writes.first[0], 0x01);
    expect(h.repo.control.writes.every((w) => w[0] != 0x02), true);
    expect(h.controller.stagedSupported, false);
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
