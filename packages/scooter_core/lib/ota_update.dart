enum OtaTransferState {
  idle,
  hashing,
  handshaking,
  transferring,
  verifying,

  /// A staged upload finished: the artifact is verified and on the scooter,
  /// waiting for an install to be requested. Settled, like success and
  /// failure, because nothing is running anywhere.
  staged,
  installing,
  pendingReboot,
  success,
  failure,
}

enum UpdatePlanPhase {
  idle,
  queryingVersions,
  fetchingIndex,
  ready,
  upToDate,
  error
}

/// Presentation policy stays in the application; HTTP codes remain structured.
class UpdateHttpError implements Exception {
  const UpdateHttpError(this.statusCode, {required this.index});
  final int statusCode;
  final bool index;
  @override
  String toString() =>
      '${index ? "Index" : "Download"} failed (HTTP $statusCode)';
}

class UpdateCheckError implements Exception {
  const UpdateCheckError(this.cause);
  final Object cause;
  @override
  String toString() => cause.toString();
}
