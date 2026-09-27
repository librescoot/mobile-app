import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

class OnlineLocationNotice extends StatelessWidget {
  const OnlineLocationNotice({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.location_off_outlined),
            title: Text(FlutterI18n.translate(context, 'online_location_disabled_title')),
            subtitle: Text(FlutterI18n.translate(context, 'online_location_disabled_description')),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      );
}
