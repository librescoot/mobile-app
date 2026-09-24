import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/widgets/header.dart';
import 'package:unustasis/ui/sheets/hibernate_sheet.dart';
import 'package:scooter_flutter/trip_commands.dart';

import 'package:unustasis/scooter_service.dart';

enum BlinkerMode { left, right, hazard, off }

enum _ScooterControlAction { unlock, lock, wake, hibernate, reboot, hardReboot }

class ControlSheet extends StatefulWidget {
  const ControlSheet({super.key});

  @override
  State<ControlSheet> createState() => _ControlSheetState();
}

class _ControlSheetState extends State<ControlSheet> with TickerProviderStateMixin {
  bool _disconnectedHandled = false;

  Widget _controlLabel(
    BuildContext context,
    IconData icon,
    String translationKey, {
    Color? iconColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 8),
        // Segment labels shrink instead of overflowing at large text sizes.
        Flexible(
          child: Text(
            FlutterI18n.translate(context, translationKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _tripError(Object error) {
    if (error is TimeoutException || error is TripResetException && error.failure == TripResetFailure.timeout) {
      return FlutterI18n.translate(context, 'trip_timeout');
    }
    if (error.toString().toLowerCase().contains('connected')) {
      return FlutterI18n.translate(context, 'trip_disconnected');
    }
    return FlutterI18n.translate(context, 'trip_error');
  }

  Future<void> _confirmTripReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(FlutterI18n.translate(dialogContext, 'trip_reset_confirm_title')),
        content: Text(FlutterI18n.translate(dialogContext, 'trip_reset_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(FlutterI18n.translate(dialogContext, 'trip_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(FlutterI18n.translate(dialogContext, 'trip_reset_now')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<ScooterService>().resetTripCounter();
      if (mounted) Fluttertoast.showToast(msg: FlutterI18n.translate(context, 'trip_reset_done'));
    } catch (error) {
      if (mounted) Fluttertoast.showToast(msg: _tripError(error));
    }
  }

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
    final blinkers = context.select<ScooterService, ({bool left, bool right})>(
      (service) => (left: service.blinkerLeft, right: service.blinkerRight),
    );
    final blinkerMode = switch (blinkers) {
      (left: true, right: true) => BlinkerMode.hazard,
      (left: true, right: false) => BlinkerMode.left,
      (left: false, right: true) => BlinkerMode.right,
      _ => BlinkerMode.off,
    };
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
            selected: blinkerMode == BlinkerMode.off ? const {} : {blinkerMode},
            onSelectionChanged: (value) async {
              final mode = value.isEmpty ? BlinkerMode.off : value.first!;
              try {
                await context.read<ScooterService>().blink(
                      left: mode == BlinkerMode.left || mode == BlinkerMode.hazard,
                      right: mode == BlinkerMode.right || mode == BlinkerMode.hazard,
                    );
              } catch (e) {
                Fluttertoast.showToast(msg: e.toString());
              }
            },
          ),
          Center(
            child: Header(
              FlutterI18n.translate(context, "controls_state_title"),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            ),
          ),
          SizedBox(
            height: 56,
            child: SegmentedButton<_ScooterControlAction>(
              expandedInsets: EdgeInsets.zero,
              style: const ButtonStyle(
                fixedSize: WidgetStatePropertyAll(Size.fromHeight(56)),
                padding: WidgetStatePropertyAll(EdgeInsets.fromLTRB(0, 18, 0, 14)),
              ),
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              selected: const <_ScooterControlAction>{},
              segments: [
                ButtonSegment(
                  value: _ScooterControlAction.unlock,
                  label: _controlLabel(
                    context,
                    Icons.lock_open_outlined,
                    "controls_unlock",
                    iconColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
                ButtonSegment(
                  value: _ScooterControlAction.lock,
                  label: _controlLabel(
                    context,
                    Icons.lock_outline_rounded,
                    "controls_lock",
                    iconColor: Theme.of(context).colorScheme.primary,
                  ),
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
          ),
          const SizedBox(height: 16),
          Selector<ScooterService, bool?>(
            selector: (context, s) => s.identity.supportsHibernateFor,
            builder: (context, supportsHibernateFor, _) {
              final probing = supportsHibernateFor == null;
              final warningColor =
                  Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
              return SizedBox(
                height: 56,
                child: SegmentedButton<_ScooterControlAction>(
                  expandedInsets: EdgeInsets.zero,
                  style: const ButtonStyle(
                    fixedSize: WidgetStatePropertyAll(Size.fromHeight(56)),
                    padding: WidgetStatePropertyAll(EdgeInsets.fromLTRB(0, 18, 0, 14)),
                  ),
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  selected: const <_ScooterControlAction>{},
                  segments: [
                    ButtonSegment(
                      value: _ScooterControlAction.wake,
                      label: _controlLabel(
                        context,
                        Icons.power_settings_new_rounded,
                        "controls_wake_up",
                        iconColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    ButtonSegment(
                      value: _ScooterControlAction.hibernate,
                      enabled: !probing,
                      label: _controlLabel(
                        context,
                        Icons.nightlight_outlined,
                        "controls_hibernate",
                        iconColor: warningColor,
                      ),
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
                ),
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
                      return SizedBox(
                        height: 56,
                        child: SegmentedButton<_ScooterControlAction>(
                          expandedInsets: EdgeInsets.zero,
                          style: const ButtonStyle(
                            fixedSize: WidgetStatePropertyAll(Size.fromHeight(56)),
                            padding: WidgetStatePropertyAll(EdgeInsets.fromLTRB(0, 18, 0, 14)),
                          ),
                          emptySelectionAllowed: true,
                          showSelectedIcon: false,
                          selected: const <_ScooterControlAction>{},
                          segments: [
                            ButtonSegment(
                              value: _ScooterControlAction.reboot,
                              label: _controlLabel(context, Icons.restart_alt_rounded, "controls_reboot"),
                            ),
                            if (permitsHardReboot)
                              ButtonSegment(
                                value: _ScooterControlAction.hardReboot,
                                label: _controlLabel(
                                  context,
                                  Icons.warning_amber_rounded,
                                  "controls_hard_reboot",
                                  iconColor: Theme.of(context).colorScheme.error,
                                ),
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
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          Selector<ScooterService, bool>(
            selector: (context, s) => s.connected && s.tripCounterSupported == true,
            builder: (context, canReset, _) {
              if (!canReset) return const SizedBox.shrink();
              final colors = Theme.of(context).colorScheme;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Header(
                      FlutterI18n.translate(context, "trip_title"),
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _confirmTripReset,
                    style: OutlinedButton.styleFrom(
                      fixedSize: const Size.fromHeight(52),
                      foregroundColor: colors.error,
                      side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(FlutterI18n.translate(context, "trip_reset_now")),
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
