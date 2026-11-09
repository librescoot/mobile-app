import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/domain/scooter_state.dart';

import '../../scooter_service.dart';
import '../dialogs/seat_warning.dart';

/// Tells the user what an installed update waits for, and offers to end the
/// wait.
///
/// The main board restarts only while the vehicle is in stand-by, so an
/// installed update sits pending for as long as the scooter stays parked or
/// ready to drive. The first time the scooter is seen in a state the app can
/// lock, a dialog asks whether to lock it now; "later" leaves a tile with the
/// same action. Locking is the home screen's lock action with its seatbox
/// confirmation, and happens only on a tap.
class OtaRebootHint extends StatefulWidget {
  const OtaRebootHint({super.key, this.onLock});

  /// Injection point for tests; defaults to the home screen's lock action.
  final Future<void> Function()? onLock;

  static bool canLock(ScooterState? state) =>
      state == ScooterState.parked ||
      state == ScooterState.ready ||
      state == ScooterState.waitingSeatbox;

  @override
  State<OtaRebootHint> createState() => _OtaRebootHintState();
}

class _OtaRebootHintState extends State<OtaRebootHint> {
  bool _asked = false;

  Future<void> _lock(ScooterService service) async {
    final onLock = widget.onLock;
    if (onLock != null) {
      await onLock();
    } else {
      await lockWithSeatConfirmation(context, service);
    }
  }

  Future<void> _ask(ScooterService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(FlutterI18n.translate(dialog, 'ls_ota_reboot_dialog_title')),
        content: Text(FlutterI18n.translate(dialog, 'ls_ota_reboot_dialog_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(FlutterI18n.translate(dialog, 'ls_ota_reboot_later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(FlutterI18n.translate(dialog, 'ls_ota_reboot_lock_and_apply')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _lock(service);
  }

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
    final lockable = OtaRebootHint.canLock(state);
    if (lockable && !_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ask(service);
      });
    }
    return ListTile(
      leading: const Icon(Icons.lock_clock),
      title: Text(FlutterI18n.translate(context, 'ls_ota_reboot_needs_lock')),
      trailing: lockable
          ? TextButton(
              onPressed: () => _lock(service),
              child: Text(FlutterI18n.translate(context, 'ls_ota_reboot_lock_now')),
            )
          : null,
    );
  }
}
