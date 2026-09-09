import 'package:flutter/material.dart';

/// Help's row hierarchy, scoped to Settings and Help rather than the app theme.
class SettingsHelpRowTheme extends StatelessWidget {
  const SettingsHelpRowTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        // Do not inherit textColor: ListTile applies it to both title and subtitle,
        // overriding their separate colors (including in SwitchListTile).
        listTileTheme: ListTileThemeData(
          iconColor: theme.colorScheme.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          minLeadingWidth: 24,
          horizontalTitleGap: 16,
          minVerticalPadding: 8,
          titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: theme.colorScheme.onSurface,
          ),
          subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
          shape: theme.listTileTheme.shape,
        ),
      ),
      child: child,
    );
  }
}
