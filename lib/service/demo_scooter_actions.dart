import 'package:scooter_core/scooter_core.dart';
import 'package:scooter_core/telemetry.dart';
import 'package:scooter_flutter/scooter_actions.dart';

/// Session-local scooter responses. No method binds a BLE command transport.
class DemoScooterActions extends ScooterActions {
  DemoScooterActions({
    required super.session,
    required super.telemetry,
    required super.settings,
    required super.effects,
    required this.changeState,
    required this.openDemoSeat,
    required this.changeUsbMode,
    required this.changeAlarmStatus,
  });

  final void Function(ScooterState) changeState;
  final void Function() openDemoSeat;
  final void Function(UsbMode) changeUsbMode;
  final void Function(AlarmStatus) changeAlarmStatus;
  bool get alarmEnabled => _values[lsKeyAlarmEnabled] == 'true';
  final _cards = <String>['D3A00001', 'D3A00002'];
  final _phones = <String>['0123456789ABCDEF0123456789ABCDEF'];
  final _aliases = <String, String>{};
  final _values = <String, String>{
    lsKeyAutoStandbySeconds: '300',
    lsKeyHibernateTimer: '3600',
    lsKeyScheduledHibernateEnabled: 'false',
    lsKeyScheduledHibernateCron: '0 3 * * *',
    lsKeyScheduledHibernateDuration: '1h',
    lsKeyBatteryKeepActiveOnSeatboxOpen: 'false',
    lsKeyAlarmEnabled: 'true',
    lsKeyAlarmHonk: 'false',
    lsKeyCellularApn: '',
    lsKeyServiceModeActive: 'false',
  };
  int _nextCard = 3;

  String addSampleKeycard() {
    final uid = 'D3A0${_nextCard.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    _nextCard++;
    _cards.add(uid);
    return uid;
  }

  @override
  Future<void> unlock({bool checkHandlebars = true, EventSource source = EventSource.app}) async {
    changeState(ScooterState.parked);
  }

  @override
  Future<void> lock(
      {bool checkHandlebars = true, bool confirmOpenSeat = false, EventSource source = EventSource.app}) async {
    changeState(ScooterState.standby);
  }

  @override
  Future<void> wakeUpAndUnlock({EventSource? source}) => unlock(source: source ?? EventSource.app);

  @override
  Future<void> wakeUp() async => changeState(ScooterState.standby);

  @override
  Future<void> openSeat({EventSource source = EventSource.app}) async => openDemoSeat();

  @override
  Future<void> disarmAlarm() async => changeAlarmStatus(AlarmStatus.disarmed);

  @override
  Future<void> blink({required bool left, required bool right}) async {}

  @override
  Future<void> hazard({int times = 1}) async {}

  @override
  Future<void> hibernate() async => changeState(ScooterState.hibernating);

  @override
  Future<void> hibernateFor(Duration wakeAfter) => hibernate();

  @override
  Future<void> hibernateCancel() async => changeState(ScooterState.parked);

  @override
  Future<void> reboot() async => changeState(ScooterState.parked);

  @override
  Future<void> hardReboot() => reboot();

  @override
  Future<void> enterUMSMode() async => changeUsbMode(UsbMode.massStorage);

  @override
  Future<void> enterNormalUsbMode() async => changeUsbMode(UsbMode.normal);

  @override
  Future<int?> countKeycards() async => _cards.length;

  @override
  Future<List<String>> listKeycards() async => List.unmodifiable(_cards);

  @override
  Future<List<String>> listPhoneKeys() async => List.unmodifiable(_phones);

  @override
  Future<List<String>> listMasterKeys() async => const ['D3A0FFFF'];

  @override
  Future<Map<String, String>> listKeyAliases() async => Map.unmodifiable(_aliases);

  @override
  Future<void> setKeyAlias(String kind, String id, String name) async {
    _aliases['$kind:$id'] = name;
  }

  @override
  Future<void> clearKeyAlias(String kind, String id) async {
    _aliases.remove('$kind:$id');
  }

  @override
  Future<void> deletePhoneKey(String fingerprint, {bool force = false}) async {
    _phones.remove(fingerprint);
    _aliases.remove('phone:$fingerprint');
  }

  @override
  Future<void> addKeycard(String uid) async {
    if (_cards.contains(uid)) throw StateError('Keycard already exists');
    _cards.add(uid);
  }

  @override
  Future<void> deleteKeycard(String uid) async {
    _cards.remove(uid);
    _aliases.remove('card:$uid');
  }

  @override
  Future<String?> getSetting(String key) async => _values[key];

  @override
  Future<void> setSetting(String key, String value) async {
    _values[key] = value;
    if (key == lsKeyAlarmEnabled) changeAlarmStatus(value == 'true' ? AlarmStatus.disarmed : AlarmStatus.disabled);
  }

  @override
  Future<void> setScheduledHibernationEnabled(bool enabled, {String? cron, Duration? wakeAfter}) async {
    if (cron != null) _values[lsKeyScheduledHibernateCron] = cron;
    if (wakeAfter != null) _values[lsKeyScheduledHibernateDuration] = formatGoDuration(wakeAfter);
    _values[lsKeyScheduledHibernateEnabled] = '$enabled';
  }

  @override
  Future<void> setServiceMode(bool enabled) => setSetting(lsKeyServiceModeActive, '$enabled');

  @override
  Future<void> setAutoStandbyTime(Duration time) => setSetting(lsKeyAutoStandbySeconds, '${time.inSeconds}');

  @override
  Future<void> setAutoHibernateTime(Duration time) => setSetting(lsKeyHibernateTimer, '${time.inSeconds}');

  @override
  Future<void> setCellularApn(String apn) => setSetting(lsKeyCellularApn, apn);

  @override
  Future<void> clearCellularApn() => setSetting(lsKeyCellularApn, '');

  @override
  Future<String?> setClock(DateTime time) async => 'time:ok';

  @override
  Future<Map<String, String?>> readInstalledVersions() async => const {
        'mdb': 'demo',
        'dbc': 'demo',
        'nrf': 'demo',
      };
}
