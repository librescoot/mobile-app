import 'dart:async';

/// Commands are deliberately not suitable for persistent delivery queues.
class CompanionRequest {
  CompanionRequest.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        scooterId = json['scooterId'] as String,
        action = json['action'] as String,
        issuedAt = json['issuedAt'] as int,
        expiresAt = json['expiresAt'] as int {
    if (json['version'] != 1 ||
        !RegExp(r'^[a-zA-Z0-9-]{16,64}$').hasMatch(id) ||
        scooterId.isEmpty ||
        scooterId.length > 128 ||
        !const ['refresh', 'lock', 'unlock', 'openSeat'].contains(action) ||
        expiresAt <= issuedAt ||
        expiresAt - issuedAt > 15000) {
      throw const FormatException('Invalid companion request');
    }
  }
  final String id, scooterId, action;
  final int issuedAt, expiresAt;
  bool validAt(int now) => issuedAt <= now + 2000 && now < expiresAt;
}

class CompanionObservation {
  const CompanionObservation(this.state, this.seatClosed);
  final String? state;
  final bool? seatClosed;

  bool confirms(String action) => switch (action) {
        'unlock' => state == 'parked',
        'lock' => state == 'stand-by',
        'openSeat' => seatClosed == false,
        'refresh' => state != null,
        _ => false,
      };
  bool allows(String action) => switch (action) {
        'unlock' => state == 'stand-by' || state == 'parked',
        'lock' ||
        'openSeat' =>
          state == 'parked' || (action == 'lock' && state == 'stand-by'),
        'refresh' => true,
        _ => false,
      };
}

/// Reads must return live values from the captured connection, not UI caches.
/// A write exception or timeout is ambiguous and must never trigger a retry.
class CompanionExecutor {
  CompanionExecutor({
    required this.current,
    required this.read,
    required this.write,
    int Function()? now,
    Future<void> Function(Duration)? delay,
  })  : now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        delay = delay ?? Future<void>.delayed;

  final bool Function(String scooterId) current;
  final Future<CompanionObservation> Function() read;
  final Future<void> Function(String action) write;
  final int Function() now;
  final Future<void> Function(Duration) delay;
  final Map<String, int> _seen = {};
  bool _busy = false;

  Future<String> execute(CompanionRequest request) async {
    _seen.removeWhere((_, expires) => expires <= now());
    if (!request.validAt(now())) return 'expired';
    if (_seen.containsKey(request.id)) return 'duplicate';
    _seen[request.id] = request.expiresAt;
    if (_busy) return 'busy';
    if (!current(request.scooterId)) return 'unavailable';
    _busy = true;
    var issued = false;
    bool valid() => request.validAt(now()) && current(request.scooterId);
    Future<T> bounded<T>(Future<T> value) => value.timeout(
        Duration(milliseconds: (request.expiresAt - now()).clamp(1, 15000)));
    try {
      final before = await bounded(read());
      if (!valid()) return 'expired';
      if (!before.allows(request.action)) return 'unsafeState';
      if (before.confirms(request.action)) return 'confirmed';
      if (request.action == 'refresh') return 'unavailable';
      issued = true;
      await bounded(write(request.action));
      while (valid()) {
        final observed = await bounded(read());
        if (!valid()) break;
        if (observed.confirms(request.action)) return 'confirmed';
        await delay(const Duration(milliseconds: 250));
      }
      return 'unknown';
    } catch (_) {
      return issued ? 'unknown' : 'unavailable';
    } finally {
      _busy = false;
    }
  }
}
