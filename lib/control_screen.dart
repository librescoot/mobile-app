import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import '../home_screen.dart';
import '../scooter_service.dart';
import 'command_service.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  Future<bool> showCloudConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
                FlutterI18n.translate(context, "cloud_command_confirm_title")),
            content: Text(
                FlutterI18n.translate(context, "cloud_command_confirm_body")),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(FlutterI18n.translate(context, "cloud_command_confirm_cancel")),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(FlutterI18n.translate(context, "cloud_command_confirm_confirm")),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "controls_title")),
        elevation: 0.0,
        bottomOpacity: 0.0,
      ),
      body: ListView(
        children: [
          Header(FlutterI18n.translate(context, "controls_state_title")),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () async {
                      await context.read<ScooterService>().executeCommand(
                            CommandType.unlock,
                            onNeedConfirmation: () =>
                                showCloudConfirmationDialog(context),
                          );
                      Navigator.of(context).pop();
                    },
                    icon: Icons.lock_open_outlined,
                    label: FlutterI18n.translate(context, "controls_unlock"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () async {
                      await context.read<ScooterService>().executeCommand(
                            CommandType.lock,
                            onNeedConfirmation: () =>
                                showCloudConfirmationDialog(context),
                          );
                      Navigator.of(context).pop();
                    },
                    icon: Icons.lock_outlined,
                    label: FlutterI18n.translate(context, "controls_lock"),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () {
                      context.read<ScooterService>().wakeUp();
                      Navigator.of(context).pop();
                    },
                    icon: Icons.wb_sunny_outlined,
                    label: FlutterI18n.translate(context, "controls_wake_up"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () {
                      context.read<ScooterService>().hibernate();
                      Navigator.of(context).pop();
                    },
                    icon: Icons.nightlight_outlined,
                    label: FlutterI18n.translate(context, "controls_hibernate"),
                  ),
                ),
              ],
            ),
          ),
          Header(FlutterI18n.translate(context, "controls_blinkers_title")),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () async {
                      await context.read<ScooterService>().executeCommand(
                            CommandType.blinkerLeft,
                            onNeedConfirmation: () =>
                                showCloudConfirmationDialog(context),
                          );
                    },
                    icon: Icons.arrow_back_ios_new_rounded,
                    label:
                        FlutterI18n.translate(context, "controls_blink_left"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () async {
                      await context.read<ScooterService>().executeCommand(
                            CommandType.blinkerRight,
                            onNeedConfirmation: () =>
                                showCloudConfirmationDialog(context),
                          );
                    },
                    icon: Icons.arrow_forward_ios_rounded,
                    label:
                        FlutterI18n.translate(context, "controls_blink_right"),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () async {
                        await context.read<ScooterService>().executeCommand(
                              CommandType.blinkerBoth,
                              onNeedConfirmation: () =>
                                  showCloudConfirmationDialog(context),
                            );
                      },
                      icon: Icons.code_rounded,
                      label: FlutterI18n.translate(
                          context, "controls_blink_hazard"),
                    ),
                  ),
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () async {
                        await context.read<ScooterService>().executeCommand(
                              CommandType.blinkerOff,
                              onNeedConfirmation: () =>
                                  showCloudConfirmationDialog(context),
                            );
                      },
                      icon: Icons.code_off_rounded,
                      label:
                          FlutterI18n.translate(context, "controls_blink_off"),
                    ),
                  ),
                ]),
          ),
          FutureBuilder<bool>(
            future: context.read<ScooterService>().isCommandAvailable(CommandType.honk),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!) {
                return Container(); // Don't show cloud section if not available
              }

              return Column(
                children: [
                  Header(FlutterI18n.translate(context, "controls_cloud_title")),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ScooterActionButton(
                            onPressed: () async {
                              await context.read<ScooterService>().executeCommand(
                                CommandType.honk,
                                onNeedConfirmation: () => showCloudConfirmationDialog(context),
                              );
                            },
                            icon: Icons.volume_up_outlined,
                            label: FlutterI18n.translate(context, "controls_honk"),
                          ),
                        ),
                        Expanded(
                          child: ScooterActionButton(
                            onPressed: () async {
                              await context.read<ScooterService>().executeCommand(
                                CommandType.locate,
                                onNeedConfirmation: () => showCloudConfirmationDialog(context),
                              );
                            },
                            icon: Icons.search_outlined,
                            label: FlutterI18n.translate(context, "controls_locate"),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ScooterActionButton(
                            onPressed: () async {
                              await context.read<ScooterService>().executeCommand(
                                CommandType.alarm,
                                onNeedConfirmation: () => showCloudConfirmationDialog(context),
                              );
                            },
                            icon: Icons.notification_important_outlined,
                            label: FlutterI18n.translate(context, "controls_alarm"),
                          ),
                        ),
                        Expanded(
                          child: ScooterActionButton(
                            onPressed: () async {
                              await context.read<ScooterService>().executeCommand(
                                CommandType.ping,
                                onNeedConfirmation: () => showCloudConfirmationDialog(context),
                              );
                            },
                            icon: Icons.cloud_sync_outlined,
                            label: FlutterI18n.translate(context, "controls_ping"),
                          ),
                        ),
                        Expanded(
                          child: ScooterActionButton(
                            onPressed: () async {
                              await context.read<ScooterService>().executeCommand(
                                CommandType.getState,
                                onNeedConfirmation: () => showCloudConfirmationDialog(context),
                              );
                            },
                            icon: Icons.refresh_outlined,
                            label: FlutterI18n.translate(context, "controls_refresh"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class Header extends StatelessWidget {
  const Header(this.title, {this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7))),
          if (subtitle != null) const SizedBox(height: 2),
          if (subtitle != null)
            Text(subtitle!,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}
