import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/theme/theme_helper.dart';

class ScooterVisual extends StatefulWidget {
  final ScooterState? state;
  final bool scanning;
  final bool blinkerLeft;
  final bool blinkerRight;
  final int? color;
  final bool winter;
  final bool aprilFools;
  final bool halloween;
  final Random? random;
  final List<int> surpriseThresholds;
  final Duration? surpriseDuration;

  const ScooterVisual({
    required this.state,
    required this.scanning,
    required this.blinkerLeft,
    required this.blinkerRight,
    this.winter = false,
    this.aprilFools = false,
    this.halloween = false,
    this.color,
    this.random,
    this.surpriseThresholds = const [42, 69, 83],
    this.surpriseDuration,
    super.key,
  });

  @override
  State<ScooterVisual> createState() => _ScooterVisualState();
}

// All scooter layers (base, light ring, beam, seasonal overlays) share these
// dimensions. Pinning the stack to this ratio keeps every layer at its final
// size from the first frame, instead of growing in as each asset decodes.
const double _scooterAspectRatio = 866 / 1800;

class _ScooterVisualState extends State<ScooterVisual> with SingleTickerProviderStateMixin {
  // controls whether the light ring is flickering:
  // when true the ring is considered hidden (flickering), when false it's visible
  bool _ringFlickering = false;

  // current AnimatedOpacity duration for the light ring. We switch this to
  // a short duration while flickering to get quick blinks, then restore it.
  Duration _ringOpacityDuration = const Duration(milliseconds: 1000);

  late final Random _rand;
  late final AnimationController _tapAnimation;
  late int _tapThreshold;
  int _tapCount = 0;
  int? _surpriseColor;
  double _shakeIntensity = 0;
  Timer? _surpriseTimer;

  // timers scheduled for flicker sequences and the loop timer
  final List<Timer> _scheduledTimers = [];
  Timer? _nextLoopTimer;

  bool get _baseOn => widget.state != null && widget.state!.isOn;

  @override
  void initState() {
    super.initState();
    _rand = widget.random ?? Random();
    _tapAnimation = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _tapThreshold = _nextTapThreshold();
    _ringFlickering = !_baseOn;
    if (widget.halloween && _baseOn) {
      // initial spooky flicker immediately
      _doFlickerSequence();
    }
  }

  @override
  void didUpdateWidget(covariant ScooterVisual oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.color != oldWidget.color ||
        (widget.state == ScooterState.disconnected && oldWidget.state != ScooterState.disconnected)) {
      _surpriseTimer?.cancel();
      _surpriseColor = null;
      _tapCount = 0;
      _tapThreshold = _nextTapThreshold();
      _tapAnimation.reset();
    }

    // If flicker flag changed or power state changed, adjust behavior
    if (widget.halloween != oldWidget.halloween) {
      if (widget.halloween && _baseOn) {
        _doFlickerSequence();
      } else {
        _cancelAllFlickers();
        setState(() {
          _ringOpacityDuration = const Duration(milliseconds: 1000);
          _ringFlickering = !_baseOn;
        });
      }
    }

    // If scooter turned on while flicker is enabled, start a sequence
    if (widget.halloween && !_baseOn && oldWidget.state != null && oldWidget.state!.isOn) {
      // turned off -> ensure ring hidden (inverted -> flickering = true)
      _cancelAllFlickers();
      setState(() => _ringFlickering = true);
    }

    if (widget.halloween && _baseOn && !(oldWidget.state?.isOn ?? false)) {
      // just turned on
      _doFlickerSequence();
    }

    // If flicker is disabled but the base on-state changed, reflect it
    if (!widget.halloween && _baseOn != (oldWidget.state != null && oldWidget.state!.isOn)) {
      setState(() => _ringFlickering = !_baseOn);
    }
  }

  @override
  void dispose() {
    _surpriseTimer?.cancel();
    _tapAnimation.dispose();
    _cancelAllFlickers();
    super.dispose();
  }

  int _nextTapThreshold() {
    assert(widget.surpriseThresholds.isNotEmpty);
    return widget.surpriseThresholds[_rand.nextInt(widget.surpriseThresholds.length)];
  }

  int get _regularColor => widget.aprilFools ? 9 : widget.color ?? 1;

  void _handleArtworkTap() {
    if (widget.state == ScooterState.disconnected || _surpriseColor != null) return;
    _tapCount++;
    final shakeStartsAt = (_tapThreshold * 0.55).floor();
    if (_tapCount >= shakeStartsAt) {
      final progress = ((_tapCount - shakeStartsAt) / (_tapThreshold - shakeStartsAt)).clamp(0.0, 1.0);
      _shakeIntensity = 0.5 + progress * 7.5;
      _tapAnimation.forward(from: 0);
    }
    if (_tapCount >= _tapThreshold) _showSurpriseSkin();
  }

  void _showSurpriseSkin() {
    final choices = [7, 8, 9].where((color) => color != _regularColor).toList();
    setState(() {
      _surpriseColor = choices[_rand.nextInt(choices.length)];
      _shakeIntensity = 8;
    });
    HapticFeedback.mediumImpact();
    _tapAnimation.forward(from: 0);
    final duration = widget.surpriseDuration ?? Duration(seconds: 10 + _rand.nextInt(21));
    _surpriseTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _surpriseColor = null;
        _tapCount = 0;
        _tapThreshold = _nextTapThreshold();
        _shakeIntensity = 0;
      });
    });
  }

  void _cancelAllFlickers() {
    for (var t in _scheduledTimers) {
      t.cancel();
    }
    _scheduledTimers.clear();
    _nextLoopTimer?.cancel();
    _nextLoopTimer = null;
  }

  void _doFlickerSequence() {
    // cancel any pending timers for an ongoing sequence
    for (var t in _scheduledTimers) {
      t.cancel();
    }
    _scheduledTimers.clear();

    // If scooter not on, don't flicker
    if (!_baseOn) return;

    // number of toggles for the spooky launch effect
    final toggles = 6 + _rand.nextInt(6); // 6..11 toggles

    // cumulative delay tracker
    int cumulative = 0;

    for (var i = 0; i < toggles; i++) {
      final ms = 1 + _rand.nextInt(300); // 1..349 ms between toggles
      cumulative += ms;
      final t = Timer(Duration(milliseconds: cumulative), () {
        if (!mounted) return;
        setState(() {
          // fast opacity during toggles
          _ringOpacityDuration = Duration(
            milliseconds: 60 + _rand.nextInt(140),
          );
          _ringFlickering = !_ringFlickering;
        });
      });
      _scheduledTimers.add(t);
    }

    // After sequence ends, restore stable visibility and duration
    cumulative += 200;
    final restore = Timer(Duration(milliseconds: cumulative), () {
      if (!mounted) return;
      setState(() {
        _ringOpacityDuration = const Duration(milliseconds: 1000);
        _ringFlickering = false; // settle to visible when on (inverted)
      });
      // schedule next loop in 10..30 seconds
      _scheduleNextLoop();
    });
    _scheduledTimers.add(restore);
  }

  void _scheduleNextLoop() {
    _nextLoopTimer?.cancel();
    final seconds = 10 + _rand.nextInt(21); // 10..30
    _nextLoopTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      if (!widget.halloween || !_baseOn) return;
      _doFlickerSequence();
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayColor = _surpriseColor ?? _regularColor;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.halloween)
          AnimatedOpacity(
            opacity: widget.state == ScooterState.disconnected ? 0 : 1,
            duration: const Duration(milliseconds: 500),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700, maxHeight: 300),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 80.0),
                child: Image(
                  fit: BoxFit.contain,
                  image: AssetImage(
                    "images/decoration/wings.webp",
                  ),
                ),
              ),
            ),
          ),
        GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.translucent,
          onTap: _handleArtworkTap,
          child: AnimatedBuilder(
            animation: _tapAnimation,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ConstrainedBox(
                // max-width instead of a tight width: when the available height is
                // the limiting factor, AspectRatio must be free to shrink the width
                // too, or the box gets squashed and the AnimatedCrossFade layers
                // (which align topStart, unlike plain Images) drift off-center.
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.55,
                ),
                child: AspectRatio(
                  aspectRatio: _scooterAspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    fit: StackFit.expand,
                    children: [
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 500),
                        firstChild: Shimmer.fromColors(
                          baseColor: context.isDarkMode ? Colors.black : Colors.black45,
                          highlightColor: widget.scanning
                              ? Colors.transparent
                              : context.isDarkMode
                                  ? Colors.black
                                  : Colors.black45,
                          enabled: widget.scanning,
                          direction: ShimmerDirection.ltr,
                          period: const Duration(seconds: 2),
                          child: const Image(
                            image: AssetImage("images/scooter/disconnected.webp"),
                          ),
                        ),
                        secondChild: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeInBack,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.72, end: 1).animate(animation),
                              child: child,
                            ),
                          ),
                          child: Image(
                            key: ValueKey('scooter-skin-$displayColor'),
                            gaplessPlayback: true,
                            image: AssetImage("images/scooter/base_$displayColor.webp"),
                          ),
                        ),
                        crossFadeState: widget.state == ScooterState.disconnected
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                      ),
                      if (widget.winter && widget.state != ScooterState.disconnected)
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 500),
                          firstChild: const Image(
                            image: AssetImage(
                              "images/scooter/seasonal/winter_on.webp",
                            ),
                          ),
                          secondChild: const Image(
                            image: AssetImage(
                              "images/scooter/seasonal/winter_off.webp",
                            ),
                          ),
                          crossFadeState: widget.state != null && widget.state!.isOn
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                        ),
                      AnimatedOpacity(
                        opacity: (widget.state != null && widget.state!.isOn) ? (_ringFlickering ? 0.5 : 1.0) : 0.0,
                        duration: _ringOpacityDuration,
                        child: const Image(
                          image: AssetImage("images/scooter/light_ring.webp"),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: widget.state == ScooterState.ready ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 1000),
                        child: const Image(
                          image: AssetImage("images/scooter/light_beam.webp"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            builder: (context, child) {
              final decay = 1 - _tapAnimation.value;
              final wave = sin(_tapAnimation.value * pi * 4);
              final offset = wave * _shakeIntensity * decay;
              return Transform.translate(
                key: const ValueKey('scooter-artwork-shake'),
                offset: Offset(offset, 0),
                child: Transform.rotate(
                  angle: offset * 0.0025,
                  child: child,
                ),
              );
            },
          ),
        ),
      ],
    );
    //BlinkerWidget(blinkerLeft: blinkerLeft, blinkerRight: blinkerRight),
  }

  IconData stateIcon() {
    if (widget.scanning) {
      return Icons.wifi_tethering;
    }
    switch (widget.state) {
      case ScooterState.standby:
        return Icons.power_settings_new;
      case ScooterState.off:
        return Icons.block;
      case ScooterState.parked:
        return Icons.local_parking;
      case ScooterState.shuttingDown:
        return Icons.settings_power;
      case ScooterState.ready:
        return Icons.check_circle;
      case ScooterState.hibernating:
        return Icons.bedtime;
      default:
        return Icons.error;
    }
  }
}

class BlinkerWidget extends StatefulWidget {
  final bool blinkerLeft;
  final bool blinkerRight;

  const BlinkerWidget({
    required this.blinkerLeft,
    required this.blinkerRight,
    super.key,
  });

  @override
  State<BlinkerWidget> createState() => _BlinkerWidgetState();
}

class _BlinkerWidgetState extends State<BlinkerWidget> {
  bool _showBlinker = true;

  // Timer to toggle the image every second
  late Timer _timer;

  @override
  void initState() {
    super.initState();

    var anyBlinker = widget.blinkerLeft || widget.blinkerRight;

    if (anyBlinker) {
      _timer = Timer.periodic(const Duration(milliseconds: 600), (Timer t) {
        setState(() => _showBlinker = !_showBlinker);
      });
    }
  }

  @override
  void dispose() {
    // Cancel the timer to avoid memory leaks
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const blinkerDuration = Duration(milliseconds: 200);

    var showBlinkerLeft = _showBlinker && widget.blinkerLeft;
    var showBlinkerRight = _showBlinker && widget.blinkerRight;

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: showBlinkerLeft ? 1.0 : 0.0,
          duration: blinkerDuration,
          child: const Image(
            image: AssetImage("images/scooter/blinker_l.webp"),
          ),
        ),
        AnimatedOpacity(
          opacity: showBlinkerRight ? 1.0 : 0.0,
          duration: blinkerDuration,
          child: const Image(
            image: AssetImage("images/scooter/blinker_r.webp"),
          ),
        ),
      ],
    );
  }
}
