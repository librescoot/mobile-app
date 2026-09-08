import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ScooterActionButton extends StatefulWidget {
  const ScooterActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.iconColor,
    this.showBubble = false,
    required this.label,
    this.holdToTrigger = false,
    this.holdInstruction,
  });

  final void Function()? onPressed;
  final IconData icon;
  final String label;
  final Color? iconColor;
  final bool showBubble;
  final bool holdToTrigger;
  final String? holdInstruction;

  @override
  State<ScooterActionButton> createState() => _ScooterActionButtonState();
}

class _ScooterActionButtonState extends State<ScooterActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _holdProgress;
  bool _holdActivated = false;

  @override
  void initState() {
    super.initState();
    _holdProgress = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..addStatusListener(_onHoldStatusChanged);
  }

  @override
  void dispose() {
    _holdProgress.dispose();
    super.dispose();
  }

  void _onHoldStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || _holdActivated || widget.onPressed == null) return;
    _holdActivated = true;
    widget.onPressed!();
  }

  void _startHold() {
    if (widget.onPressed == null) return;
    _holdActivated = false;
    _holdProgress.forward(from: 0);
  }

  void _finishHold() {
    if (!_holdActivated && widget.holdInstruction != null) {
      Fluttertoast.showToast(msg: widget.holdInstruction!);
    }
    _holdProgress.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final mainColor = widget.iconColor ?? (enabled ? colors.primary : colors.onSurface.withValues(alpha: 0.28));

    final button = SizedBox(
      width: 68,
      height: 56,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: mainColor,
          backgroundColor: enabled ? colors.surface.withValues(alpha: 0.92) : Colors.transparent,
          side: BorderSide(color: mainColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: widget.holdToTrigger ? (enabled ? () {} : null) : widget.onPressed,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.holdToTrigger && enabled)
              AnimatedBuilder(
                animation: _holdProgress,
                builder: (context, child) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _holdProgress.value,
                    heightFactor: 1,
                    child: ColoredBox(color: mainColor.withValues(alpha: 0.24)),
                  ),
                ),
              ),
            Center(child: Icon(widget.icon, color: mainColor, size: 26)),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.holdToTrigger)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _startHold(),
                  onTapUp: (_) => _finishHold(),
                  onTapCancel: () => _holdProgress.value = 0,
                  child: IgnorePointer(child: button),
                )
              else
                button,
              if (widget.showBubble)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: mainColor),
          ),
        ],
      ),
    );
  }
}
