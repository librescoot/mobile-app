import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/scooter_battery.dart' as core;
import 'package:unustasis/domain/scooter_battery.dart';

void main() {
  test('legacy battery types are shared while images remain app-owned', () {
    expect(ScooterBatteryType.primary, same(core.ScooterBatteryType.primary));
    expect(AUXChargingState.bulkCharge, same(core.AUXChargingState.bulkCharge));
    expect(ScooterBatteryType.values.map((value) => (value as Enum).name),
        ['primary', 'secondary', 'aux', 'cbb', 'nfc']);
    expect(AUXChargingState.values.map((value) => (value as Enum).name),
        ['floatCharge', 'absorptionCharge', 'bulkCharge', 'none']);
    for (final type in [ScooterBatteryType.primary, ScooterBatteryType.secondary, ScooterBatteryType.nfc]) {
      expect(type.imagePath(86), 'images/battery/batt_full.webp');
      expect(type.imagePath(85), 'images/battery/batt_75.webp');
      expect(type.imagePath(60), 'images/battery/batt_50.webp');
      expect(type.imagePath(35), 'images/battery/batt_25.webp');
      expect(type.imagePath(10), 'images/battery/batt_empty.webp');
    }
    expect(ScooterBatteryType.cbb.imagePath(100), 'images/battery/batt_internal.webp');
    expect(ScooterBatteryType.aux.imagePath(0), 'images/battery/batt_internal.webp');
  });
}
