import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A text-valued selector under SettingsHelpRowTheme, retaining DropdownButton's
/// immediate-selection behavior (the loading hint may also be a spinner).
class SettingsDropdownTile<T> extends StatelessWidget {
  const SettingsDropdownTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.unlistedValueLabel,
    super.key,
  });

  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final T? value;
  final Widget hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget? unlistedValueLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final theme = Theme.of(context);
      final direction = Directionality.of(context);
      final rowTheme = ListTileTheme.of(context);
      final padding = rowTheme.contentPadding!.resolve(direction);
      final rowWidth = constraints.maxWidth - padding.horizontal;
      // The value claims the width it needs and the description column gives it
      // up, so a longer option stays on its own line beside the description.
      // Only a value that cannot fit even in a generous share of the row drops
      // below it.
      // Room the selector spends on its arrow and padding before the label.
      const dropdownChrome = 40.0;
      const maxTrailingShare = 0.6;
      // Firmware settings need not match this app's shortcut presets. Retain
      // the reported value as an additional option, without writing a default.
      var menuItems = items;
      Widget label = hint;
      if (value != null) {
        final selected = items.indexWhere((item) => item.value == value);
        if (selected >= 0) {
          label = items[selected].child;
        } else {
          label = unlistedValueLabel ?? Text('$value');
          menuItems = [...items, DropdownMenuItem<T>(value: value, child: label)];
        }
      }
      var labelStyle = theme.textTheme.titleMedium;
      if (label is Text) labelStyle = labelStyle?.merge(label.style);
      if (MediaQuery.boldTextOf(context)) labelStyle = labelStyle?.copyWith(fontWeight: FontWeight.bold);
      final painter = TextPainter(
        text: label is Text ? TextSpan(text: label.data, style: labelStyle) : const TextSpan(text: ''),
        textDirection: direction,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      // A non-text label (the loading spinner) has no intrinsic width of its
      // own, so it keeps the previous share of the row.
      final labelWidth = label is Text ? painter.width : null;
      painter.dispose();
      final trailingWidth =
          labelWidth == null ? rowWidth * 0.32 : math.min(labelWidth + dropdownChrome, rowWidth * maxTrailingShare);
      final belowDescription = labelWidth != null && labelWidth + dropdownChrome > trailingWidth;
      final dropdown = ConstrainedBox(
        // On its own line the selector has the whole row to itself, so it does
        // not inherit the leading icon's indent.
        constraints: BoxConstraints(maxWidth: belowDescription ? rowWidth : trailingWidth),
        child: IntrinsicWidth(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: value == null ? hint : null,
              items: menuItems,
              onChanged: onChanged,
              isExpanded: true,
              itemHeight: null,
              menuWidth: 144,
              // Offstage options must not make the closed selector wider/taller.
              selectedItemBuilder: (context) => [
                for (final item in menuItems)
                  if (item.value == value)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                      child: Align(widthFactor: 1, heightFactor: 1, child: item.child),
                    )
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      );
      return ListTile(
        leading: leading,
        title: title,
        subtitle: belowDescription
            ? Column(
                // Stretch, so the selector's own line is as wide as the row and
                // the value is not squeezed into the description's width.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  subtitle,
                  const SizedBox(height: 4),
                  Align(alignment: AlignmentDirectional.centerEnd, child: dropdown),
                ],
              )
            : subtitle,
        trailing: belowDescription ? null : dropdown,
      );
    });
  }
}
