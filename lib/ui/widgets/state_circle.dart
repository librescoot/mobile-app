import 'package:flutter/material.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/theme/theme_helper.dart';

class StateCircle extends StatefulWidget {
  const StateCircle({
    super.key,
    required bool scanning,
    required bool connected,
    bool halloween = false,
    bool fall = false,
    bool alarm = false,
    required ScooterState? scooterState,
  })  : _scanning = scanning,
        _connected = connected,
        _halloween = halloween,
        _fall = fall,
        _alarm = alarm,
        _scooterState = scooterState;

  final bool _scanning;
  final bool _connected;
  final bool _halloween;
  final bool _fall;

  /// The alarm is sounding, so the circle breathes red instead of sitting flat.
  final bool _alarm;
  final ScooterState? _scooterState;

  @override
  State<StateCircle> createState() => _StateCircleState();
}

class _StateCircleState extends State<StateCircle> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget._alarm) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StateCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._alarm && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget._alarm && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  double get _scale {
    if (widget._alarm) return 1.5 + 0.12 * _pulse.value;
    if (!widget._connected) return widget._scanning ? 1.5 : 0;
    switch (widget._scooterState) {
      case ScooterState.parked:
        return 1.5;
      case ScooterState.ready:
        return 3;
      default:
        return 1.2;
    }
  }

  List<BoxShadow>? _glow(Color error) {
    if (widget._alarm) {
      return [
        BoxShadow(
          color: error.withValues(alpha: 0.35 + 0.4 * _pulse.value),
          blurRadius: 70 + 60 * _pulse.value,
          spreadRadius: 4 + 10 * _pulse.value,
        ),
      ];
    }
    if (widget._halloween && widget._scooterState?.isOn == true) {
      return [
        const BoxShadow(
          color: Color(0xFFFFCD6F),
          blurRadius: 100,
          spreadRadius: 10,
        ),
      ];
    }
    return null;
  }

  Color _fill(BuildContext context) {
    if (widget._alarm) {
      return Theme.of(context).colorScheme.error.withValues(alpha: 0.20 + 0.35 * _pulse.value);
    }
    final primary = Theme.of(context).colorScheme.primary;
    if (widget._scooterState?.isOn == true) {
      if (context.isDarkMode) {
        return widget._halloween
            ? const Color(0xFFFFCD6F).withAlpha(50)
            : HSLColor.fromColor(primary).withLightness(0.18).toColor();
      }
      return widget._fall
          ? const Color(0xFFFF8400).withAlpha(100)
          : HSLColor.fromColor(primary).withAlpha(0.3).toColor();
    }
    return context.isDarkMode
        ? const Color(0xFF303437)
        : Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.7);
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final size = MediaQuery.sizeOf(context).width * 0.85;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => AnimatedScale(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutBack,
        scale: _scale,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            boxShadow: _glow(error),
            image: widget._halloween
                ? DecorationImage(
                    image: const AssetImage("images/decoration/moon.webp"),
                    fit: BoxFit.cover,
                    opacity: widget._connected ? 0.2 : 0.05,
                  )
                : null,
            shape: BoxShape.circle,
            color: _fill(context),
          ),
        ),
      ),
    );
  }
}
