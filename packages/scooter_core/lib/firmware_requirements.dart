final _releaseVersion = RegExp(
  r'^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);
final _datedVersion = RegExp(
    r'^(?:nightly|testing)-([0-9]{4})([0-9]{2})([0-9]{2})(?:T([0-9]{2})([0-9]{2})([0-9]{2}))?$');

bool supportsBluetoothFirmwareUpdates(String? mdbVersion) {
  if (mdbVersion == null) return false;
  final version = mdbVersion.trim();
  final release = _releaseVersion.firstMatch(version);
  if (release != null) {
    final prerelease = release.group(4);
    if (prerelease != null &&
        prerelease.split('.').any((part) =>
            RegExp(r'^[0-9]+$').hasMatch(part) &&
            part.length > 1 &&
            part.startsWith('0'))) {
      return false;
    }
    final major = BigInt.parse(release.group(1)!);
    final minor = BigInt.parse(release.group(2)!);
    final patch = BigInt.parse(release.group(3)!);
    if (major != BigInt.one) return major > BigInt.one;
    if (minor != BigInt.two) return minor > BigInt.two;
    return patch > BigInt.zero || (patch == BigInt.zero && prerelease == null);
  }

  final dated = _datedVersion.firstMatch(version);
  if (dated == null) return false;
  final year = int.parse(dated.group(1)!);
  final month = int.parse(dated.group(2)!);
  final day = int.parse(dated.group(3)!);
  final hour = int.parse(dated.group(4) ?? '0');
  final minute = int.parse(dated.group(5) ?? '0');
  final second = int.parse(dated.group(6) ?? '0');
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      date.hour != hour ||
      date.minute != minute ||
      date.second != second) {
    return false;
  }
  return !date.isBefore(DateTime.utc(2026, 8, 3));
}
