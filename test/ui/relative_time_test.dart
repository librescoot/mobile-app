import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/presentation/relative_time.dart';

void main() {
  testWidgets('relative-time formatting preserves existing abbreviated labels',
      (tester) async {
    final values = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        final now = DateTime.now();
        for (final age in [
          const Duration(days: 8),
          const Duration(days: 2),
          const Duration(hours: 3),
          const Duration(minutes: 4),
        ]) {
          values.add(now.subtract(age).calculateExactTimeDifferenceInShort(context));
        }
        return const SizedBox.shrink();
      }),
    ));
    expect(values, ['1W', '2D', '3H', '4M']);
  });
}
