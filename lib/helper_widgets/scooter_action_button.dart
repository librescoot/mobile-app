import 'package:flutter/material.dart';

class ScooterActionButton extends StatelessWidget {
  const ScooterActionButton({
    super.key,
    required void Function()? onPressed,
    required IconData icon,
    Color? iconColor,
    bool showBubble = false,
    required String label,
  })  : _onPressed = onPressed,
        _icon = icon,
        _iconColor = iconColor,
        _label = label,
        _showBubble = showBubble;

  final void Function()? _onPressed;
  final IconData _icon;
  final String _label;
  final Color? _iconColor;
  final bool _showBubble;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = _onPressed != null;
    final mainColor = _iconColor ?? (enabled ? colors.primary : colors.onSurface.withValues(alpha: 0.28));

    return Semantics(
      button: true,
      enabled: enabled,
      label: _label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
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
                  onPressed: _onPressed,
                  child: Icon(_icon, color: mainColor, size: 26),
                ),
              ),
              if (_showBubble)
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
            _label,
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
