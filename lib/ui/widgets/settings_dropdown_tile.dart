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
    super.key,
  });

  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final T? value;
  final Widget hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final theme = Theme.of(context);
      final direction = Directionality.of(context);
      final rowTheme = ListTileTheme.of(context);
      final padding = rowTheme.contentPadding!.resolve(direction);
      final textInset = rowTheme.minLeadingWidth! + rowTheme.horizontalTitleGap!;
      final rowWidth = constraints.maxWidth - padding.horizontal;
      final trailingWidth = rowWidth * 0.32;
      final label = value == null ? hint : items.firstWhere((item) => item.value == value).child;
      // ListTile caps trailing height at 56dp. Measure the actual scaled label
      // so a narrow display or translation can grow below the description.
      var labelStyle = theme.textTheme.titleMedium;
      if (label is Text) labelStyle = labelStyle?.merge(label.style);
      if (MediaQuery.boldTextOf(context)) labelStyle = labelStyle?.copyWith(fontWeight: FontWeight.bold);
      final painter = TextPainter(
        text: label is Text ? TextSpan(text: label.data, style: labelStyle) : const TextSpan(text: ''),
        textDirection: direction,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: trailingWidth - 24);
      final belowDescription = painter.height > 56;
      painter.dispose();
      final dropdown = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: belowDescription ? rowWidth - textInset : trailingWidth),
        child: IntrinsicWidth(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: value == null ? hint : null,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              itemHeight: null,
              menuWidth: 144,
              // Offstage options must not make the closed selector wider/taller.
              selectedItemBuilder: (context) => [
                for (final item in items)
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
                crossAxisAlignment: CrossAxisAlignment.start,
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
