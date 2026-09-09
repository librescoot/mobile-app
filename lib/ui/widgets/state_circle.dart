import 'package:flutter/material.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/theme/theme_helper.dart';

class StateCircle extends StatelessWidget {
  const StateCircle({
    super.key,
    required bool scanning,
    required bool connected,
    bool halloween = false,
    bool fall = false,
    required ScooterState? scooterState,
  })  : _scanning = scanning,
        _connected = connected,
        _halloween = halloween,
        _fall = fall,
        _scooterState = scooterState;

  final bool _scanning;
  final bool _connected;
  final bool _halloween;
  final bool _fall;
  final ScooterState? _scooterState;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutBack,
      scale: _connected
          ? _scooterState == ScooterState.parked
              ? 1.5
              : (_scooterState == ScooterState.ready)
                  ? 3
                  : 1.2
          : _scanning
              ? 1.5
              : 0,
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.width,
        decoration: BoxDecoration(
          boxShadow: _halloween && _scooterState?.isOn == true
              ? [
                  BoxShadow(
                    color: Color(0xFFFFCD6F).withAlpha(150),
                    blurRadius: 100,
                    spreadRadius: 10,
                  ),
                ]
              : null,
          image: _halloween
              ? DecorationImage(
                  image: AssetImage("images/decoration/moon.webp"), fit: BoxFit.cover, opacity: _connected ? 0.2 : 0.05)
              : null,
          shape: BoxShape.circle,
          color: _scooterState?.isOn == true
              ? context.isDarkMode
                  ? _halloween
                      ? Color(0xFFFFCD6F).withAlpha(50)
                      : HSLColor.fromColor(
                          Theme.of(context).colorScheme.primary,
                        ).withLightness(0.18).toColor()
                  : _fall
                      ? Color(0xFFFF8400).withAlpha(100)
                      : HSLColor.fromColor(
                          Theme.of(context).colorScheme.primary,
                        ).withAlpha(0.3).toColor()
              : context.isDarkMode
                  ? const Color(0xFF303437)
                  : Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
