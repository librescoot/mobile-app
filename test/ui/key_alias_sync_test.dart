import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/key_alias_sync.dart';

void main() {
  test('conflicts stay separate and only unopposed enrolled names are imported', () {
    final scooterNames = {
      'card:04010203': 'Scooter name',
      'phone:0123456789ABCDEF0123456789ABCDEF': 'Phone',
    };
    final localNames = {
      '04010203': 'Old phone name',
      'AABBCCDD': ' Spare card ',
      '00112233': 'Master',
      'DEADBEEF': 'Not enrolled',
    };

    final plan = planKeyAliasImport(
      ['04010203', 'AABBCCDD', '00112233', '04010203'],
      scooterNames,
      localNames,
    );

    expect(plan.names, {'AABBCCDD': 'Spare card', '00112233': 'Master'});
    expect(plan.conflicts, hasLength(1));
    expect(plan.conflicts.single.uid, '04010203');
    expect(plan.conflicts.single.localName, 'Old phone name');
    expect(plan.conflicts.single.scooterName, 'Scooter name');
    expect(scooterNames['card:04010203'], 'Scooter name');
    expect(localNames['04010203'], 'Old phone name');
    expect(plan.invalidLocalNames, isFalse);
  });

  test('matching local and scooter names need no synchronization', () {
    final plan = planKeyAliasImport(
      ['04010203'],
      {'card:04010203': 'Daily card'},
      {'04010203': 'Daily card'},
    );

    expect(plan.names, isEmpty);
    expect(plan.conflicts, isEmpty);
    expect(plan.invalidLocalNames, isFalse);
  });

  test('invalid legacy names cannot be sent to scooter', () {
    final plan = planKeyAliasImport(
      ['AABBCCDD', '00112233'],
      {},
      {'AABBCCDD': 'x' * 33, '00112233': 'Valid'},
    );
    expect(plan.names, {'00112233': 'Valid'});
    expect(plan.conflicts, isEmpty);
    expect(plan.invalidLocalNames, isTrue);
  });
}
