import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/theme/scooter_colors.dart';
import 'package:unustasis/ui/widgets/eclipse_backdrop.dart';
import 'package:unustasis/ui/widgets/scooter_color_swatch.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';
import 'package:unustasis/ui/widgets/scooter_visual.dart';

class ColorPickerDialog extends StatefulWidget {
  final int initialValue;
  final String scooterName;

  const ColorPickerDialog({
    super.key,
    required this.initialValue,
    required this.scooterName,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late int selectedValue;
  bool _showSide = false;
  bool _limitedColorsUnlocked = false;
  int _previewTapCount = 0;

  @override
  void initState() {
    super.initState();
    selectedValue = canonicalScooterColor(widget.initialValue);
  }

  List<int> get _availableColors {
    final values = [...standardScooterColorValues];
    if (_limitedColorsUnlocked || widget.scooterName == magic("Rpyvcfr")) values.add(7);
    if (_limitedColorsUnlocked || widget.scooterName == magic("Xbev")) values.add(8);
    if (widget.scooterName == magic("Ubire")) values.add(9);
    if (selectedValue >= 7 && !values.contains(selectedValue)) values.add(selectedValue);
    return values;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: widget.scooterName.trim().isEmpty
          ? null
          : Center(
              child: Text(
                widget.scooterName,
                textAlign: TextAlign.center,
              ),
            ),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _preview(),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 16,
              children: [
                for (final value in _availableColors) _colorOption(value),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(FlutterI18n.translate(context, "stats_rename_cancel")),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: Text(FlutterI18n.translate(context, "stats_rename_save")),
          onPressed: () => Navigator.of(context).pop(selectedValue),
        ),
      ],
    );
  }

  Widget _preview() {
    final switchLabel = FlutterI18n.translate(
      context,
      _showSide ? "color_preview_show_front" : "color_preview_show_side",
    );
    return Semantics(
      button: true,
      label: switchLabel,
      child: Tooltip(
        message: switchLabel,
        child: InkWell(
          borderRadius: BorderRadius.circular(120),
          child: SizedBox(
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (selectedValue == 7)
                  const EclipseBackdrop(diameter: 228)
                else
                  Container(
                    key: const ValueKey('scooter-color-preview-backdrop'),
                    width: 228,
                    height: 228,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                Positioned.fill(child: _anglePreview()),
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('scooter-color-preview'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _handlePreviewTap,
                  ),
                ),
                Positioned(
                  right: 26,
                  bottom: 25,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(Icons.threesixty, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handlePreviewTap() {
    _previewTapCount++;
    final unlock = !_limitedColorsUnlocked && _previewTapCount >= 23;
    setState(() {
      _showSide = !_showSide;
      if (unlock) _limitedColorsUnlocked = true;
    });
    if (unlock) HapticFeedback.mediumImpact();
  }

  Widget _anglePreview() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final amount = Curves.easeInOutCubic.transform(animation.value);
          return Opacity(
            opacity: amount,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(0.04 + amount * 0.96, 1, 1),
              child: child,
            ),
          );
        },
      ),
      child: KeyedSubtree(
        key: ValueKey(_showSide ? 'side-angle' : 'front-angle'),
        child: _colorDissolve(side: _showSide),
      ),
    );
  }

  Widget _colorDissolve({required bool side}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: side
          ? ScooterSideVisual(
              key: ValueKey('scooter-color-side-$selectedValue'),
              imagePath: 'images/scooter/side_$selectedValue.webp',
              height: 160,
              showBackdrop: false,
            )
          : SizedBox(
              key: ValueKey('scooter-color-front-$selectedValue'),
              width: 132,
              height: 246,
              child: ScooterVisual(
                color: selectedValue,
                state: ScooterState.parked,
                scanning: false,
                blinkerLeft: false,
                blinkerRight: false,
                showEclipseBackdrop: false,
              ),
            ),
    );
  }

  Widget _colorOption(int value) {
    final scooterColor = scooterColors[value]!;
    final label = FlutterI18n.translate(context, "color_${scooterColor.simpleName}");
    final selected = selectedValue == value;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: ValueKey('scooter-color-option-$value'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => selectedValue = value),
        child: SizedBox(
          width: 82,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScooterColorSwatch(
                  scooterColor: scooterColor,
                  selected: selected,
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String magic(String input) {
    return input.split('').map((char) {
      if (RegExp(r'[a-z]').hasMatch(char)) {
        return String.fromCharCode(((char.codeUnitAt(0) - 97 + 13) % 26) + 97);
      } else if (RegExp(r'[A-Z]').hasMatch(char)) {
        return String.fromCharCode(((char.codeUnitAt(0) - 65 + 13) % 26) + 65);
      } else {
        return char;
      }
    }).join('');
  }
}

Future<int?> showColorDialog(int initialValue, String scooterName, BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (BuildContext context) {
      return ColorPickerDialog(
        initialValue: initialValue,
        scooterName: scooterName,
      );
    },
  );
}
