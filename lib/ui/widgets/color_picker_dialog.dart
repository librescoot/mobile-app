import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/theme/scooter_colors.dart';
import 'package:unustasis/ui/widgets/eclipse_backdrop.dart';
import 'package:unustasis/ui/widgets/rendered_scooter_artwork.dart';
import 'package:unustasis/ui/widgets/scooter_color_swatch.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';
import 'package:unustasis/ui/widgets/scooter_visual.dart';

class ScooterColorSelection {
  const ScooterColorSelection.builtIn(this.color)
      : customColor = null,
        matte = true;

  const ScooterColorSelection.custom(this.customColor, {required this.matte}) : color = 3;

  final int color;
  final String? customColor;
  final bool matte;

  bool get isCustom => customColor != null;
}

class ColorPickerDialog extends StatefulWidget {
  final int initialValue;
  final String? initialCustomColor;
  final bool initialCustomColorMatte;
  final String scooterName;

  const ColorPickerDialog({
    super.key,
    required this.initialValue,
    this.initialCustomColor,
    this.initialCustomColorMatte = true,
    required this.scooterName,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late int selectedValue;
  String? _customColor;
  late bool _customColorMatte;
  bool _showSide = false;
  bool _limitedColorsUnlocked = false;
  int _previewTapCount = 0;

  @override
  void initState() {
    super.initState();
    selectedValue = canonicalScooterColor(widget.initialValue);
    _customColor = widget.initialCustomColor;
    _customColorMatte = widget.initialCustomColorMatte;
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
                _customColorOption(),
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
          onPressed: () => Navigator.of(context).pop(
            _customColor == null
                ? ScooterColorSelection.builtIn(selectedValue)
                : ScooterColorSelection.custom(_customColor!, matte: _customColorMatte),
          ),
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
                if (_customColor == null && selectedValue == 7)
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
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
          child: RotationTransition(
            turns: Tween<double>(begin: _showSide ? -0.025 : 0.025, end: 0).animate(animation),
            child: child,
          ),
        ),
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
      child: side ? _sideArtwork() : _frontArtwork(),
    );
  }

  Widget _colorOption(int value) {
    final scooterColor = scooterColors[value]!;
    final label = FlutterI18n.translate(context, "color_${scooterColor.simpleName}");
    final selected = _customColor == null && selectedValue == value;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: ValueKey('scooter-color-option-$value'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          selectedValue = value;
          _customColor = null;
        }),
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

  Widget _frontArtwork() {
    final renderedColor =
        _customColor ?? (usesLayeredScooterArtwork(selectedValue) ? layeredScooterColor(selectedValue) : null);
    final matte = _customColor == null ? layeredScooterColorIsMatte(selectedValue) : _customColorMatte;
    if (renderedColor != null) {
      return SizedBox(
        key: ValueKey('scooter-color-front-$renderedColor-$matte'),
        width: 132,
        height: 246,
        child: RenderedScooterArtwork(
          view: ScooterArtworkView.front,
          color: renderedColor,
          matte: matte,
        ),
      );
    }
    return SizedBox(
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
    );
  }

  Widget _sideArtwork() {
    final renderedColor =
        _customColor ?? (usesLayeredScooterArtwork(selectedValue) ? layeredScooterColor(selectedValue) : null);
    final matte = _customColor == null ? layeredScooterColorIsMatte(selectedValue) : _customColorMatte;
    if (renderedColor != null) {
      return RenderedScooterArtwork(
        key: ValueKey('scooter-color-side-$renderedColor-$matte'),
        view: ScooterArtworkView.side,
        color: renderedColor,
        matte: matte,
        height: 160,
      );
    }
    return ScooterSideVisual(
      key: ValueKey('scooter-color-side-$selectedValue'),
      imagePath: 'images/scooter/side_$selectedValue.webp',
      height: 160,
      showBackdrop: false,
    );
  }

  Widget _customColorOption() {
    final selected = _customColor != null;
    final color = _customColor == null
        ? const Color(0xFF7D5FFF)
        : Color(0xFF000000 | int.parse(_customColor!.substring(1), radix: 16));
    final scooterColor = ScooterColor(
      value: -1,
      displayColor: color,
      simpleName: 'custom',
      finish: _customColorMatte ? ScooterColorFinish.matte : ScooterColorFinish.glossy,
    );
    final label = FlutterI18n.translate(context, 'color_custom');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: const ValueKey('scooter-color-option-custom'),
        borderRadius: BorderRadius.circular(12),
        onTap: _editCustomColor,
        child: SizedBox(
          width: 82,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ScooterColorSwatch(
                      scooterColor: scooterColor,
                      selected: selected,
                    ),
                    if (!selected)
                      Icon(
                        Icons.add,
                        color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                  ],
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

  Future<void> _editCustomColor() async {
    final selection = await showDialog<_CustomColorSelection>(
      context: context,
      builder: (context) => _CustomColorDialog(
        initialColor: _customColor ?? layeredScooterColor(selectedValue),
        initialMatte: _customColor == null ? layeredScooterColorIsMatte(selectedValue) : _customColorMatte,
      ),
    );
    if (selection == null || !mounted) return;
    setState(() {
      _customColor = selection.color;
      _customColorMatte = selection.matte;
    });
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

class _CustomColorSelection {
  const _CustomColorSelection(this.color, this.matte);

  final String color;
  final bool matte;
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({
    required this.initialColor,
    required this.initialMatte,
  });

  final String initialColor;
  final bool initialMatte;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late int _red;
  late int _green;
  late int _blue;
  late bool _matte;

  @override
  void initState() {
    super.initState();
    final value = int.parse(widget.initialColor.substring(1), radix: 16);
    _red = (value >> 16) & 0xFF;
    _green = (value >> 8) & 0xFF;
    _blue = value & 0xFF;
    _matte = widget.initialMatte;
  }

  String get _hex =>
      '#${_red.toRadixString(16).padLeft(2, '0')}${_green.toRadixString(16).padLeft(2, '0')}${_blue.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  Color get _color => Color(0xFF000000 | (_red << 16) | (_green << 8) | _blue);

  @override
  Widget build(BuildContext context) {
    final previewColor = ScooterColor(
      value: -2,
      displayColor: _color,
      simpleName: 'custom',
      finish: _matte ? ScooterColorFinish.matte : ScooterColorFinish.glossy,
    );
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(FlutterI18n.translate(context, 'color_custom')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_CustomColorSelection(_hex, _matte)),
              child: Text(FlutterI18n.translate(context, 'stats_rename_save')),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            key: const ValueKey('custom-color-backdrop'),
                            width: min(340, constraints.maxWidth * 0.78),
                            height: min(340, constraints.maxWidth * 0.78),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          RenderedScooterArtwork(
                            key: const ValueKey('custom-color-preview'),
                            view: ScooterArtworkView.front,
                            color: _hex,
                            matte: _matte,
                            height: min(400, constraints.maxHeight * 0.48),
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ScooterColorSwatch(
                              scooterColor: previewColor,
                              selected: false,
                              size: 52,
                            ),
                            const SizedBox(width: 14),
                            Text(_hex, style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _channelSlider('R', _red, (value) => _red = value),
                        _channelSlider('G', _green, (value) => _green = value),
                        _channelSlider('B', _blue, (value) => _blue = value),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(FlutterI18n.translate(context, 'color_custom_matte')),
                          value: _matte,
                          onChanged: (value) => setState(() => _matte = value),
                        ),
                      ],
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

  Widget _channelSlider(String label, int value, ValueChanged<int> update) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            label: '$value',
            onChanged: (next) => setState(() => update(next.round())),
          ),
        ),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.end)),
      ],
    );
  }
}

Future<ScooterColorSelection?> showColorDialog(
  int initialValue,
  String scooterName,
  BuildContext context, {
  String? initialCustomColor,
  bool initialCustomColorMatte = true,
}) {
  return showDialog<ScooterColorSelection>(
    context: context,
    builder: (BuildContext context) {
      return ColorPickerDialog(
        initialValue: initialValue,
        initialCustomColor: initialCustomColor,
        initialCustomColorMatte: initialCustomColorMatte,
        scooterName: scooterName,
      );
    },
  );
}
