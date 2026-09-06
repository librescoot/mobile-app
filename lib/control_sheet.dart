import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../domain/scooter_state.dart';
import '../helper_widgets/header.dart';
import '../hibernate_sheet.dart';
import '../scooter_service.dart';

enum BlinkerMode { left, right, hazard, off }

enum _ScooterControlAction { unlock, lock, wake, hibernate, reboot, hardReboot }

class ControlSheet extends StatefulWidget {
  const ControlSheet({super.key});

  @override
  State<ControlSheet> createState() => _ControlSheetState();
}

class _ControlSheetState extends State<ControlSheet> with TickerProviderStateMixin {
  BlinkerMode _blinkerMode = BlinkerMode.off;
  bool _disconnectedHandled = false;
  Future<bool> _confirmHardReboot(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(FlutterI18n.translate(context, "controls_hard_reboot_confirm_title")),
            content: Text(FlutterI18n.translate(context, "controls_hard_reboot_confirm_message")),
            actions: [
              TextButton(
                child: Text(FlutterI18n.translate(context, "cancel")),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.onSurface,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(FlutterI18n.translate(context, "controls_hard_reboot_confirm_button")),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // listen to connection state and close if disconnected
          Selector<ScooterService, bool>(
            selector: (context, s) => s.connected,
            shouldRebuild: (prev, next) => !_disconnectedHandled && prev != next,
            builder: (context, connected, _) {
              if (!connected && !_disconnectedHandled) {
                _disconnectedHandled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _blinkerMode = BlinkerMode.off;
                  });
                  Navigator.of(context).pop();
                });
              }
              return const SizedBox.shrink();
            },
          ),
          Center(
              child: Header(
            FlutterI18n.translate(context, "controls_blinkers_title"),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          )),
          SegmentedButton<BlinkerMode?>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            style: ButtonStyle(
              padding: WidgetStatePropertyAll<EdgeInsets>(
                const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            segments: const [
              ButtonSegment<BlinkerMode?>(
                value: BlinkerMode.left,
                icon: Icon(Icons.chevron_left_rounded, size: 24),
              ),
              ButtonSegment<BlinkerMode?>(
                value: BlinkerMode.hazard,
                icon: Icon(Icons.warning_amber_rounded, size: 24),
              ),
              ButtonSegment<BlinkerMode?>(
                value: BlinkerMode.right,
                icon: Icon(Icons.chevron_right_rounded, size: 24),
              ),
            ],
            selected: {_blinkerMode},
            onSelectionChanged: (value) {
              if (value.isNotEmpty) {
                try {
                  context.read<ScooterService>().blink(
                        left: value.first == BlinkerMode.left || value.first == BlinkerMode.hazard,
                        right: value.first == BlinkerMode.right || value.first == BlinkerMode.hazard,
                      );
                  setState(() {
                    _blinkerMode = value.first!;
                  });
                } catch (e) {
                  Fluttertoast.showToast(msg: e.toString());
                }
              } else {
                try {
                  context.read<ScooterService>().blink(left: false, right: false);
                  setState(() {
                    _blinkerMode = BlinkerMode.off;
                  });
                } catch (e) {
                  Fluttertoast.showToast(msg: e.toString());
                }
              }
            },
          ),
          Center(
            child: Header(
              FlutterI18n.translate(context, "controls_state_title"),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            ),
          ),
          SegmentedButton<_ScooterControlAction>(
            expandedInsets: EdgeInsets.zero,
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 16)),
            ),
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            selected: const <_ScooterControlAction>{},
            segments: [
              ButtonSegment(
                value: _ScooterControlAction.unlock,
                icon: Icon(Icons.lock_open_outlined, color: Theme.of(context).colorScheme.primary),
                label: Text(FlutterI18n.translate(context, "controls_unlock")),
              ),
              ButtonSegment(
                value: _ScooterControlAction.lock,
                icon: Icon(Icons.lock_outline_rounded, color: Theme.of(context).colorScheme.primary),
                label: Text(FlutterI18n.translate(context, "controls_lock")),
              ),
            ],
            onSelectionChanged: (selection) {
              try {
                if (selection.first == _ScooterControlAction.unlock) {
                  context.read<ScooterService>().unlock();
                } else {
                  context.read<ScooterService>().lock();
                }
              } catch (e) {
                Fluttertoast.showToast(msg: e.toString());
              }
            },
          ),
          const SizedBox(height: 16),
          Selector<ScooterService, bool?>(
            selector: (context, s) => s.identity.supportsHibernateFor,
            builder: (context, supportsHibernateFor, _) {
              final probing = supportsHibernateFor == null;
              final warningColor =
                  Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
              return SegmentedButton<_ScooterControlAction>(
                expandedInsets: EdgeInsets.zero,
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 16)),
                ),
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                selected: const <_ScooterControlAction>{},
                segments: [
                  ButtonSegment(
                    value: _ScooterControlAction.wake,
                    icon: Icon(Icons.power_settings_new_rounded, color: Theme.of(context).colorScheme.primary),
                    label: Text(FlutterI18n.translate(context, "controls_wake_up")),
                  ),
                  ButtonSegment(
                    value: _ScooterControlAction.hibernate,
                    enabled: !probing,
                    icon: Icon(Icons.nightlight_outlined, color: warningColor),
                    label: Text(FlutterI18n.translate(context, "controls_hibernate")),
                  ),
                ],
                onSelectionChanged: (selection) async {
                  if (selection.first == _ScooterControlAction.wake) {
                    try {
                      context.read<ScooterService>().wakeUp();
                      Navigator.of(context).pop();
                    } catch (e) {
                      Fluttertoast.showToast(msg: e.toString());
                    }
                    return;
                  }

                  final service = context.read<ScooterService>();
                  if (supportsHibernateFor == true) {
                    final done = await showModalBottomSheet<bool>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (context) => const HibernateSheet(),
                    );
                    if (!context.mounted) return;
                    if (done == true || !service.connected) Navigator.of(context).pop();
                  } else {
                    try {
                      service.hibernate();
                      Navigator.of(context).pop();
                    } catch (e) {
                      Fluttertoast.showToast(msg: e.toString());
                    }
                  }
                },
              );
            },
          ),
          Selector<ScooterService, bool>(
            selector: (context, s) => s.identity.isLibrescoot == true,
            builder: (context, isLibrescoot, _) {
              if (!isLibrescoot) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Selector<ScooterService, bool>(
                    selector: (context, s) => s.state?.permitsHardReboot == true,
                    builder: (context, permitsHardReboot, _) {
                      return SegmentedButton<_ScooterControlAction>(
                        expandedInsets: EdgeInsets.zero,
                        style: const ButtonStyle(
                          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 16)),
                        ),
                        emptySelectionAllowed: true,
                        showSelectedIcon: false,
                        selected: const <_ScooterControlAction>{},
                        segments: [
                          ButtonSegment(
                            value: _ScooterControlAction.reboot,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: Text(FlutterI18n.translate(context, "controls_reboot")),
                          ),
                          if (permitsHardReboot)
                            ButtonSegment(
                              value: _ScooterControlAction.hardReboot,
                              icon: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
                              label: Text(FlutterI18n.translate(context, "controls_hard_reboot")),
                            ),
                        ],
                        onSelectionChanged: (selection) async {
                          if (selection.first == _ScooterControlAction.reboot) {
                            try {
                              await context.read<ScooterService>().reboot();
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                            } catch (e) {
                              Fluttertoast.showToast(msg: e.toString());
                            }
                            return;
                          }

                          final confirmed = await _confirmHardReboot(context);
                          if (!mounted || !confirmed) return;
                          try {
                            if (!context.mounted) return;
                            await context.read<ScooterService>().hardReboot();
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                          } catch (e) {
                            Fluttertoast.showToast(msg: e.toString());
                          }
                        },
                      );
                    },
                  ),
                ],
              );
            },
          ),
          SizedBox(height: 64),
        ],
      ),
    );
  }
}
