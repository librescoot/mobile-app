import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:scooter_core/update_planner.dart';
import 'package:scooter_core/ota_protocol.dart';

import 'firmware_queries.dart';
import 'ota_transfer_service.dart';
import 'scooter_session.dart';
import 'src/ble/characteristic_repository.dart';

export 'package:scooter_core/ota_update.dart';

/// Distribution URL, HTTP transport and channel selection are app policy.
abstract interface class UpdateReleaseProvider {
  Future<List<FirmwareRelease>> fetchIndex(String channel);
  Future<UpdateBundleDownload> fetchBundle(FirmwareAsset asset);
}

class UpdateBundleDownload {
  const UpdateBundleDownload(
      {required this.bytes, required this.close, this.length});
  final Stream<List<int>> bytes;
  final int? length;
  final void Function() close;
}

enum OtaAvailability { ready, sessionNotReady, serviceMissing, firmwareUnsupported }

/// Lifecycle of one artifact the user picked to push over Bluetooth.
enum ManualUploadStatus { pending, uploading, staged, applied, failed }

/// One local artifact queued for a Bluetooth upload, with the board it belongs
/// to. Full images are uploaded in staging mode and installed only when the user
/// asks for it, so several artifacts — a delta chain, both boards — can be
/// uploaded in one sitting, the way a USB update directory is filled.
class ManualUpload {
  ManualUpload({required this.file, required this.name, required this.component});

  final File file;
  final String name;
  final int component;
  ManualUploadStatus status = ManualUploadStatus.pending;
  double progress = 0;
  String? error;

  bool get isMender => name.endsWith('.mender');

  /// The bundle ID sent in START: a full image drops the ".mender" extension
  /// (the scooter appends it when staging), a delta keeps its own so
  /// update-service dispatches on it. Mirrors UpdateStep.bundleId and
  /// bluetooth-service's staging rules.
  String get bundleId => isMender
      ? name.substring(0, name.length - '.mender'.length)
      : name;

  /// Whether the scooter would accept this name as a bundle ID at all. A file
  /// that fails this is reported before a single byte is sent.
  bool get usableName {
    final id = bundleId;
    return id.isNotEmpty &&
        id.length <= 64 &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(id);
  }
}

/// One update workflow per existing application session, not per screen.
/// Binding consumes the sole session's tokens; it never connects or retries BLE.
class UpdateController extends ChangeNotifier {
  UpdateController(
      {required this.session,
      required this.provider,
      required this.cacheDirectory,
      required this.channel,
      this.onTargetCaptured,
      this.supportsFirmware,
      OtaTransferService? transfer})
      : transfer = transfer ?? OtaTransferService() {
    this.transfer.addListener(_changed);
  }
  final ScooterSession session;
  final UpdateReleaseProvider provider;
  final Future<Directory> Function() cacheDirectory;
  final OtaTransferService transfer;

  /// App-owned name/identity presentation is captured once per fresh operation,
  /// before state publication. Reconnection recovery retains that capture.
  final void Function(String id)? onTargetCaptured;
  final bool Function()? supportsFirmware;
  final _log = Logger('UpdateController');
  SessionConnection? _connection;
  CharacteristicRepository? _repository;
  bool _disposed = false;
  bool _working = false;
  bool _refreshOnReady = false;
  ({String channel, bool channelSwitch})? _interruptedPlanning;
  String? targetId;
  UpdatePlanPhase phase = UpdatePlanPhase.idle;
  String channel;
  String? inferredChannel;
  bool channelSwitch = false;
  String? mdbVersion, dbcVersion;
  List<FirmwareRelease> _releases = [];
  UpdatePlan? plan;
  bool downloading = false;
  double downloadProgress = 0;
  Object? error;

  /// Artifacts the user picked for a manual upload, in upload order. Kept here
  /// rather than in the screen so leaving and reopening it does not lose a
  /// queue that is still being pushed.
  final List<ManualUpload> manualUploads = [];
  bool manualUploading = false;

  /// Component whose staged artifacts are being installed, if any.
  int? manualApplyingComponent;
  Object? manualError;

  bool manualHasStaged(int component) => manualUploads
      .any((u) => u.component == component && u.status == ManualUploadStatus.staged);

  bool get manualHasAnyStaged => manualUploads.any((u) => u.status == ManualUploadStatus.staged);
  bool get refreshing =>
      phase == UpdatePlanPhase.queryingVersions ||
      phase == UpdatePlanPhase.fetchingIndex;
  bool get busy => _working || transfer.active;
  OtaAvailability get otaAvailability {
    if (_connection?.isCurrent != true || _repository == null) {
      return OtaAvailability.sessionNotReady;
    }
    if (_repository!.otaAvailable != true) return OtaAvailability.serviceMissing;
    if (supportsFirmware?.call() == false) return OtaAvailability.firmwareUnsupported;
    return OtaAvailability.ready;
  }

  bool get otaAvailable => otaAvailability == OtaAvailability.ready;

  void _changed() {
    if (_disposed) return;
    // Mirror the live transfer into the entry it belongs to, so the queue shows
    // per-artifact progress without the screen having to correlate them.
    if (manualUploading) {
      for (final upload in manualUploads) {
        if (upload.status == ManualUploadStatus.uploading) {
          upload.progress = transfer.progress;
        }
      }
    }
    notifyListeners();
  }

  void bind(SessionConnection connection, CharacteristicRepository repository) {
    _connection = connection;
    _repository = repository;
  }

  void invalidate() {
    // Readiness belongs to the captured session, not a later binding that has
    // not reached ready yet. Interrupted planning itself survives disconnect.
    _refreshOnReady = false;
    _connection = null;
    _repository = null;
    transfer.invalidate();
  }

  /// Recover one interrupted plan, or re-plan after an acknowledged install's
  /// reboot. This consumes session readiness; it is not a retry loop.
  void sessionReady() {
    if (_disposed || _connection?.isCurrent != true) return;
    if (_working) {
      _refreshOnReady = true;
      return;
    }
    final interrupted = _interruptedPlanning;
    if (interrupted != null &&
        phase == UpdatePlanPhase.idle &&
        plan == null &&
        error == null &&
        transfer.state == OtaTransferState.idle &&
        !transfer.awaitingReconnect) {
      unawaited(refresh(
          selectedChannel: interrupted.channel,
          channelSwitch: interrupted.channelSwitch));
    } else if (transfer.state == OtaTransferState.pendingReboot ||
        transfer.state == OtaTransferState.success ||
        transfer.awaitingReconnect) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    invalidate();
    transfer.removeListener(_changed);
    transfer.dispose();
    super.dispose();
  }

  Future<void> refresh(
      {bool channelSwitch = false, String? selectedChannel}) async {
    if (_disposed || busy) return;
    if (transfer.awaitingReconnect && _connection?.id != targetId) return;
    _working = true;
    // An accepted explicit check/channel choice supersedes deferred planning.
    _interruptedPlanning = null;
    var planningStarted = false;
    var planningSettled = false;
    final connection = _connection;
    final repo = _repository;
    final operationCurrent = session.captureOperationFreshness();
    bool current() =>
        !_disposed &&
        operationCurrent() &&
        identical(connection, _connection) &&
        (connection == null || connection.isCurrent);
    try {
      if ((transfer.state == OtaTransferState.idle ||
              transfer.awaitingReconnect) &&
          connection != null &&
          otaAvailable &&
          current()) {
        try {
          final recovering = transfer.awaitingReconnect;
          final adopted = await transfer
              .syncFromScooter(connection.device, repo!, isCurrent: current,
                  onAdopting: () {
            if (!recovering) {
              targetId = connection.id;
              onTargetCaptured?.call(connection.id);
              if (current()) _changed();
            }
          });
          if (!current() || adopted) return;
        } catch (e) {
          _log.warning('OTA status sync failed: $e');
        }
      }
      if (!current() || transfer.awaitingReconnect) return;
      transfer.reset();
      if (!current()) return;
      if (selectedChannel != null) channel = selectedChannel;
      this.channelSwitch = channelSwitch;
      planningStarted = true;
      phase = UpdatePlanPhase.queryingVersions;
      plan = null;
      error = null;
      _changed();
      String? mdb, dbc;
      var mdbHdelta = false, dbcHdelta = false;
      if (connection != null && repo != null) {
        try {
          if (!current()) return;
          mdb = await getInstalledVersionCommand(connection.device, repo, 'mdb',
              isCurrent: current);
        } catch (e) {
          _log.warning('MDB version query failed: $e');
        }
        if (!current()) return;
        try {
          dbc = await getInstalledVersionCommand(connection.device, repo, 'dbc',
              isCurrent: current);
        } catch (e) {
          _log.warning('DBC version query failed: $e');
        }
        if (!current()) return;
        try {
          mdbHdelta = await supportsHdeltaCommand(connection.device, repo, 'mdb', isCurrent: current);
        } catch (e) {
          _log.fine('MDB hdelta probe unavailable: $e');
        }
        if (!current()) return;
        try {
          dbcHdelta = await supportsHdeltaCommand(connection.device, repo, 'dbc', isCurrent: current);
        } catch (e) {
          _log.fine('DBC hdelta probe unavailable: $e');
        }
      }
      if (!current()) return;
      mdbVersion = mdb;
      dbcVersion = dbc;
      inferredChannel = UpdatePlanner.inferChannel(mdb);
      if (!channelSwitch && inferredChannel != null) channel = inferredChannel!;
      phase = UpdatePlanPhase.fetchingIndex;
      _changed();
      if (!current()) return;
      final releases = await provider.fetchIndex(channel);
      if (!current()) return;
      final nextPlan = UpdatePlanner.buildPlan(
          releases: releases,
          channel: channel,
          mdbVersion: mdb,
          dbcVersion: dbc,
          channelSwitch: channelSwitch,
          mdbSupportsHdelta: mdbHdelta,
          dbcSupportsHdelta: dbcHdelta);
      // Keep cache maintenance in the same operation: it cannot race a newly
      // started download and delete its file after publishing a ready plan.
      await _pruneDownloads(nextPlan, current);
      if (!current()) return;
      _releases = releases;
      plan = nextPlan;
      phase =
          nextPlan.upToDate ? UpdatePlanPhase.upToDate : UpdatePlanPhase.ready;
      planningSettled = true;
      _changed();
    } catch (e) {
      if (current()) {
        error = UpdateCheckError(e);
        phase = UpdatePlanPhase.error;
        planningSettled = true;
        _changed();
      }
    } finally {
      if (planningStarted && !planningSettled && !current() && !_disposed) {
        _interruptedPlanning = (channel: channel, channelSwitch: channelSwitch);
      }
      if (refreshing) phase = UpdatePlanPhase.idle;
      _working = false;
      _changed();
      if (_refreshOnReady) {
        _refreshOnReady = false;
        sessionReady();
      }
    }
  }

  Future<void> executeStep(UpdateStep step) async {
    if (_disposed || busy || transfer.awaitingReconnect) return;
    final connection = _connection;
    final repo = _repository;
    if (connection == null || repo == null || !otaAvailable) return;
    bool current() =>
        !_disposed &&
        identical(connection, _connection) &&
        connection.isCurrent &&
        otaAvailable;
    _working = true;
    _interruptedPlanning = null;
    downloading = true; // Includes cache lookup/checksum, not just HTTP bytes.
    downloadProgress = 0;
    error = null;
    try {
      targetId = connection.id;
      onTargetCaptured?.call(connection.id);
      if (!current()) return;
      transfer.activeStep = step;
      _changed();
      if (!current()) return;
      // Validate before deriving a cache path as well as before the wire START.
      final bundleId = step.bundleId;
      final bundle = await _downloadBundle(step.asset, current);
      if (!current()) return;
      downloading = false;
      _changed();
      if (!current()) return;
      if (step.asset.isHdelta) {
        final board = step.component == OtaProtocol.componentDbc ? 'dbc' : 'mdb';
        if (!await supportsHdeltaCommand(connection.device, repo, board, isCurrent: current)) {
          throw StateError('Board no longer confirms hdelta support; refresh the update plan');
        }
      }
      if (!current()) return;
      await transfer.transfer(connection.device, repo, bundle,
          bundleId: bundleId, component: step.component, isCurrent: current);
    } catch (e) {
      if (current()) {
        error = e;
        _changed();
      }
    } finally {
      downloading = false;
      _working = false;
      _changed();
      if (_refreshOnReady) {
        _refreshOnReady = false;
        sessionReady();
      }
    }
  }

  /// Same-release full image first, then the channel's latest supported full.
  /// The caller still obtains the existing full-image confirmation dialog.
  UpdateStep? fullImageInstead(UpdateStep deltaStep) {
    final variant = UpdatePlanner.variantFor(deltaStep.component);
    var release = deltaStep.release;
    var asset = release.menderAsset(variant);
    if (asset == null) {
      final latest = UpdatePlanner.latestFull(_releases, channel, variant);
      asset = latest?.menderAsset(variant);
      if (latest == null || asset == null) return null;
      release = latest;
    }
    return UpdateStep(
        component: deltaStep.component,
        release: release,
        asset: asset,
        kind: StepKind.full);
  }

  /// The board an artifact belongs to, read from its filename. Release assets
  /// carry the variant (librescoot-unu-mdb-…, librescoot-unu-dbc-…); anything
  /// ambiguous stays on [fallback], which the caller sets from the user's
  /// choice.
  static int componentForName(String name, int fallback) {
    if (name.contains('unu-dbc')) return OtaProtocol.componentDbc;
    if (name.contains('unu-mdb')) return OtaProtocol.componentMdb;
    return fallback;
  }

  /// Adds local artifacts to the manual upload queue. Names the scooter cannot
  /// accept are queued as failures so the list explains itself instead of
  /// silently dropping a file.
  void addManualUploads(List<File> files,
      {int fallbackComponent = OtaProtocol.componentMdb}) {
    if (_disposed) return;
    manualError = null;
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      manualUploads.add(ManualUpload(
        file: file,
        name: name,
        component: componentForName(name, fallbackComponent),
      ));
    }
    _changed();
  }

  void removeManualUpload(ManualUpload upload) {
    if (_disposed || manualUploading) return;
    manualUploads.remove(upload);
    _changed();
  }

  void clearManualUploads() {
    if (_disposed || manualUploading) return;
    manualUploads.clear();
    manualError = null;
    _changed();
  }

  /// Pushes every queued artifact to the scooter, one after another. Each one
  /// is verified by the scooter on completion and left staged; nothing is
  /// installed until [applyManualUploads] is called for its board.
  ///
  /// Failures are recorded per artifact and the queue continues: one bad file
  /// should not cost the user the rest of the evening's uploads, and a resumed
  /// transfer picks up where the scooter left it.
  Future<void> uploadManualUploads() async {
    if (_disposed || busy || manualUploading || manualUploads.isEmpty) return;
    final connection = _connection;
    final repo = _repository;
    if (connection == null || repo == null || !otaAvailable) return;
    bool current() =>
        !_disposed &&
        identical(connection, _connection) &&
        connection.isCurrent &&
        otaAvailable;

    manualUploading = true;
    manualError = null;
    _working = true;
    _changed();
    try {
      targetId = connection.id;
      onTargetCaptured?.call(connection.id);
      for (final upload in manualUploads) {
        if (!current()) return;
        if (upload.status == ManualUploadStatus.staged ||
            upload.status == ManualUploadStatus.applied) {
          continue;
        }
        upload.status = ManualUploadStatus.uploading;
        upload.error = null;
        upload.progress = 0;
        _changed();
        try {
          if (!upload.usableName) {
            throw StateError('The scooter cannot accept this file name');
          }
          if (!await upload.file.exists()) {
            throw StateError('File no longer available');
          }
          await transfer.stage(connection.device, repo, upload.file,
              bundleId: upload.bundleId,
              component: upload.component,
              isCurrent: current);
          if (!current()) return;
          upload.status = ManualUploadStatus.staged;
          upload.progress = 1;
        } catch (e) {
          upload.status = ManualUploadStatus.failed;
          upload.error = e.toString();
        }
        _changed();
      }
    } finally {
      manualUploading = false;
      _working = false;
      _changed();
      if (_refreshOnReady) {
        _refreshOnReady = false;
        sessionReady();
      }
    }
  }

  /// Installs everything staged for [component]. Retries are possible from the
  /// same button: a failed apply leaves its artifacts staged.
  Future<void> applyManualUploads(int component) async {
    if (_disposed || busy || manualUploading) return;
    final connection = _connection;
    final repo = _repository;
    if (connection == null || repo == null || !otaAvailable) return;
    bool current() =>
        !_disposed &&
        identical(connection, _connection) &&
        connection.isCurrent &&
        otaAvailable;

    manualApplyingComponent = component;
    manualError = null;
    _working = true;
    _changed();
    try {
      await transfer.applyStaged(connection.device, repo,
          component: component, isCurrent: current);
      if (!current()) return;
      for (final upload in manualUploads) {
        if (upload.component == component &&
            upload.status == ManualUploadStatus.staged) {
          upload.status = ManualUploadStatus.applied;
        }
      }
    } catch (e) {
      manualError = e;
    } finally {
      manualApplyingComponent = null;
      _working = false;
      _changed();
      if (_refreshOnReady) {
        _refreshOnReady = false;
        sessionReady();
      }
    }
  }

  Future<void> _pruneDownloads(UpdatePlan plan, bool Function() current) async {
    try {
      final dir = await cacheDirectory();
      if (!current() || !await dir.exists()) return;
      final keep = {for (final step in plan.steps) step.asset.name};
      await for (final entry in dir.list()) {
        if (!current()) return;
        if (entry is! File || keep.contains(entry.uri.pathSegments.last)) {
          continue;
        }
        await entry.delete();
      }
    } catch (e) {
      _log.warning('Bundle cleanup failed: $e');
    }
  }

  Future<File> _downloadBundle(
      FirmwareAsset asset, bool Function() current) async {
    void check() {
      if (!current()) throw StateError('Update session replaced');
    }

    final dir = await cacheDirectory();
    check();
    final file = File('${dir.path}/${asset.name}');
    if (await file.exists() && await file.length() == asset.size) {
      check();
      await _verifyBundle(file, asset);
      check();
      return file;
    }
    check();
    await file.parent.create(recursive: true);
    check();
    final response = await provider.fetchBundle(asset);
    try {
      check();
      final total = response.length ?? asset.size;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.bytes) {
          check();
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            downloadProgress = received / total;
            _changed();
          }
        }
      } finally {
        await sink.close();
      }
      check();
      await _verifyBundle(file, asset);
      check();
      return file;
    } finally {
      response.close();
    }
  }

  Future<void> _verifyBundle(File file, FirmwareAsset asset) async {
    if (asset.sha256.isEmpty) return;
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() == asset.sha256.toLowerCase()) return;
    try {
      await file.delete();
    } catch (e) {
      _log.warning('Deleting corrupt bundle failed: $e');
    }
    throw 'Downloaded bundle is corrupt (checksum mismatch), please retry';
  }
}
