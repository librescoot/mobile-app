/// Mutable persistence contract; implementations own their setter side effects.
abstract interface class SavedScooterRecord {
  String get name;
  set name(String name);

  int get color;
  set color(int color);

  DateTime get lastPing;
  set lastPing(DateTime lastPing);

  bool get autoConnect;
  set autoConnect(bool autoConnect);

  // Per-scooter keyless behaviour. The distance threshold stays global.
  bool get autoUnlock;
  set autoUnlock(bool autoUnlock);

  bool get hazardLocking;
  set hazardLocking(bool hazardLocking);

  bool get openSeatOnUnlock;
  set openSeatOnUnlock(bool openSeatOnUnlock);

  Map<String, dynamic> toJson();
}
