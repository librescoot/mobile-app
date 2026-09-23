import 'package:scooter_core/actions.dart';

class KeyAliasImport {
  const KeyAliasImport(this.names, this.invalidLocalNames);
  final Map<String, String> names;
  final bool invalidLocalNames;
}

/// Only enrolled physical cards without scooter names receive local names.
KeyAliasImport planKeyAliasImport(
    Iterable<String> enrolledCards, Map<String, String> scooterNames, Map<String, String> localNames) {
  final names = <String, String>{};
  var invalid = false;
  for (final uid in enrolledCards.toSet()) {
    if (scooterNames.containsKey('card:$uid')) continue;
    final local = localNames[uid]?.trim();
    if (local == null || local.isEmpty) continue;
    if (checkKeyAlias(local) != null) {
      invalid = true;
      continue;
    }
    names[uid] = local;
  }
  return KeyAliasImport(names, invalid);
}
