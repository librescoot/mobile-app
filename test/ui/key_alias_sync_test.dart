import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/key_alias_sync.dart';

void main() {
  test('scooter names win and only enrolled cards are imported', () {
    final plan = planKeyAliasImport(
      ['04010203', 'AABBCCDD', '00112233', '04010203'],
      {'card:04010203': 'Scooter name', 'phone:0123456789ABCDEF0123456789ABCDEF': 'Phone'},
      {
        '04010203': 'Old phone name',
        'AABBCCDD': ' Spare card ',
        '00112233': 'Master',
        'DEADBEEF': 'Not enrolled',
      },
    );
    expect(plan.names, {'AABBCCDD': 'Spare card', '00112233': 'Master'});
    expect(plan.invalidLocalNames, isFalse);
  });

  test('invalid legacy names cannot be sent to scooter', () {
    final plan = planKeyAliasImport(
      ['AABBCCDD', '00112233'],
      {},
      {'AABBCCDD': 'x' * 33, '00112233': 'Valid'},
    );
    expect(plan.names, {'00112233': 'Valid'});
    expect(plan.invalidLocalNames, isTrue);
  });
}
