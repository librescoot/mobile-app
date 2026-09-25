import 'package:scooter_core/actions.dart';

enum KeyAliasChoice { local, scooter }

class KeyAliasConflict {
  const KeyAliasConflict({
    required this.uid,
    required this.localName,
    required this.scooterName,
  });

  final String uid;
  final String localName;
  final String scooterName;
}

class KeyAliasImport {
  const KeyAliasImport(this.names, this.conflicts, this.invalidLocalNames);

  final Map<String, String> names;
  final List<KeyAliasConflict> conflicts;
  final bool invalidLocalNames;
}

/// Imports unopposed local names and leaves conflicting sources for the user.
KeyAliasImport planKeyAliasImport(
    Iterable<String> enrolledCards, Map<String, String> scooterNames, Map<String, String> localNames) {
  final names = <String, String>{};
  final conflicts = <KeyAliasConflict>[];
  var invalid = false;
  for (final uid in enrolledCards.toSet()) {
    final local = localNames[uid]?.trim();
    if (local == null || local.isEmpty) continue;
    if (checkKeyAlias(local) != null) {
      invalid = true;
      continue;
    }
    final scooter = scooterNames['card:$uid'];
    if (scooter == null) {
      names[uid] = local;
    } else if (scooter != local) {
      conflicts.add(KeyAliasConflict(uid: uid, localName: local, scooterName: scooter));
    }
  }
  return KeyAliasImport(names, conflicts, invalid);
}
