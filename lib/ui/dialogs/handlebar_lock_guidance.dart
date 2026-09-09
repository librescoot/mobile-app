import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_core/actions.dart' show ActionEvent;
import 'package:unustasis/scooter_service.dart';

/// Passive, session-owned guidance. Its lifetime is not a firmware countdown:
/// the vehicle's positioning window starts at actual locking, not at the write.
class HandlebarLockGuidance extends StatefulWidget {
  const HandlebarLockGuidance({
    super.key,
    required this.service,
    required this.action,
    required this.onDismiss,
  });

  final ScooterService service;
  final ActionEvent action;
  final VoidCallback onDismiss;

  @override
  State<HandlebarLockGuidance> createState() => _HandlebarLockGuidanceState();
}

// Home owns lifecycle suppression/removal, including before this child mounts.
class _HandlebarLockGuidanceState extends State<HandlebarLockGuidance> {
  late final Timer _timeout;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
    _timeout = Timer(const Duration(seconds: 45), _dismiss);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changed();
    });
  }

  void _changed() {
    if (!mounted || _dismissed) return;
    final service = widget.service;
    final connection = service.actions.session.currentConnection;
    if (!service.connected ||
        connection?.isCurrent != true ||
        connection!.id != widget.action.scooterId ||
        connection.generation != widget.action.generation ||
        service.handlebarsLocked == true) {
      _dismiss();
      return;
    }
    setState(() {});
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _timeout.cancel();
    // Dismissal alone never reports success or issues another command.
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timeout.cancel();
    widget.service.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    // WaitingSeatbox has not started steering-lock positioning. Nor does a
    // successful command write prove the vehicle accepted a lock from Parked.
    final shuttingDown = service.state == ScooterState.shuttingDown || service.state == ScooterState.standby;
    if (_dismissed || !shuttingDown || service.vehicleState == ScooterVehicleState.waitingSeatbox) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(FlutterI18n.translate(context, 'handlebar_lock_waiting'))),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: _dismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
