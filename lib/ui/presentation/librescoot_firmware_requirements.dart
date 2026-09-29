/// Minimum Librescoot releases with the BLE support used by these settings.
/// A capability answer remains authoritative for the connected scooter.
abstract final class LibrescootFirmwareRequirements {
  static const base = '1.0';
  static const scheduledHibernation = '1.1';
  static const ota = '1.2';
  static const serviceMode = '1.4';
}
