import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/scooter_service.dart';

/// Unlock failure retains its separate rider action; lock waiting is passive.
class HandlebarWarning extends StatelessWidget {
  const HandlebarWarning({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Lottie.asset(
            "assets/anim/handlebars.json",
            height: 160,
          ),
          const SizedBox(height: 24),
          Text(FlutterI18n.translate(context, "locked_handlebar_alert_title")),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            Text(FlutterI18n.translate(context, "locked_handlebar_alert_body")),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('OK'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text(FlutterI18n.translate(context, "locked_handlebar_alert_action")),
          onPressed: () {
            context.read<ScooterService>().lock();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
