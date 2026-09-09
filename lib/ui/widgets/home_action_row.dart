import 'package:flutter/material.dart';

/// Equal side columns keep the primary action on the screen's centerline.
class HomeActionRow extends StatelessWidget {
  const HomeActionRow({super.key, required this.leading, required this.primary, required this.trailing});

  final Widget leading;
  final Widget primary;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Center the 56dp side controls against the 72dp primary control,
            // independently of how many lines their labels occupy.
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: Center(child: leading))),
            SizedBox(width: 136, child: primary),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: Center(child: trailing))),
          ],
        ),
      );
}
