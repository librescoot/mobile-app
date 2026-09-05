import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  const Header(
    this.title, {
    this.subtitle,
    this.icon,
    this.padding = const EdgeInsets.fromLTRB(16, 24, 16, 4),
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 18,
                        fontWeight: FontWeight.normal,
                      ),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
              ],
            ],
          ),
          if (subtitle != null) const SizedBox(height: 2),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}
