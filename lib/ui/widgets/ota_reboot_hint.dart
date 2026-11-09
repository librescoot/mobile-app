import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/domain/scooter_state.dart';

import '../../scooter_service.dart';
import '../dialogs/seat_warning.dart';

/// Tells the user what an installed update is waiting for.
///
/// The main board restarts only while the vehicle is in stand-by, so an
/// installed update sits pending for as long as the scooter stays parked or
/// ready to drive. The button locks it, the same action as the lock button on
/// the home screen with its seatbox confirmation; nothing is locked without a
/// tap, because someone may be sitting on it.
class OtaRebootHint extends StatelessWidget {
  const OtaRebootHint({super.key, this.onLock});

  /// Injection point for tests; defaults to the home screen's lock action.
  final Future<void> Function()? onLock;

  static bool canLock(ScooterState? state) =>
      state == ScooterState.parked ||
      state == ScooterState.ready ||
      state == ScooterState.waitingSeatbox;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final state = service.state;
    if (!service.connected || state == null) return const SizedBox.shrink();
    if (state == ScooterState.standby) {
      return ListTile(
        leading: const Icon(Icons.restart_alt),
        title: Text(FlutterI18n.translate(context, 'ls_ota_reboot_standby')),
      );
    }
    final lockable = canLock(state);
    return ListTile(
      leading: const Icon(Icons.lock_clock),
      title: Text(FlutterI18n.translate(context, 'ls_ota_reboot_needs_lock')),
      trailing: lockable
          ? TextButton(
              onPressed: () async {
                if (onLock != null) {
                  await onLock!();
                } else {
                  await lockWithSeatConfirmation(context, service);
                }
              },
              child: Text(FlutterI18n.translate(context, 'ls_ota_reboot_lock_now')),
            )
          : null,
    );
  }
}
