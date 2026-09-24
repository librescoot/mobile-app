import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scooter_core/actions.dart';

import 'package:unustasis/feature_flags.dart';
import 'package:unustasis/ui/dialogs/keycard_add_dialog.dart';
import 'package:unustasis/ui/key_alias_sync.dart';
import 'package:unustasis/scooter_service.dart';
import '../wide_layout.dart';

class LsKeycardScreen extends StatefulWidget {
  const LsKeycardScreen({super.key});

  @override
  State<LsKeycardScreen> createState() => _LsKeycardScreenState();
}

class _LsKeycardScreenState extends State<LsKeycardScreen> {
  List<String> keycards = [];
  List<String> _enrolledPhones = [];
  bool _loadingPhones = false;
  String? _phoneListError;
  String? _removingPhone;
  String? _phoneListScooterId;
  bool _phoneListAvailable = false;
  bool _reloadPhonesAfterCurrent = false;
  String? _phoneFingerprint;
  String? _phoneKeyError;
  bool _creatingPhoneKey = false;
  static const _phoneKeyChannel = MethodChannel('org.librescoot.mobile/phone_key');

  Future<void> _restorePhoneKey() async {
    if (!Platform.isAndroid) return;
    try {
      final id = await _phoneKeyChannel.invokeMethod<String>('existingFingerprint');
      if (id != null && mounted) {
        _stopBackgroundNfcScan();
        setState(() => _phoneFingerprint = id);
      }
    } catch (_) {
      // Physical-card scanning remains available on devices without HCE.
    }
  }

  Future<void> _setUpPhoneKey() async {
    _stopBackgroundNfcScan(); // Reader mode competes with HCE on the same phone.
    setState(() {
      _creatingPhoneKey = true;
      _phoneKeyError = null;
    });
    try {
      final id = await _phoneKeyChannel.invokeMethod<String>('fingerprint');
      if (!mounted) return;
      setState(() => _phoneFingerprint = id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _phoneKeyError = e.toString());
      _startBackgroundNfcScan();
    } finally {
      if (mounted) setState(() => _creatingPhoneKey = false);
    }
  }

  Map<String, String> _aliases = {};
  Map<String, String> _localAliases = {};
  List<String> _masterCards = [];
  bool _loadingAliases = false;
  Future<void> _aliasQueue = Future.value();
  String? _aliasError;
  String? _aliasScooterId;
  bool _aliasAvailable = false;
  late final Future<void> _localAliasLoad;
  bool _isLoadingKeycards = false;
  bool _reloadKeycardsAfterCurrent = false;
  bool _isBackgroundScanning = false;
  String? _highlightedUid;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _localAliasLoad = _loadAliases();
    if (phoneKeyFeatureEnabled) _restorePhoneKey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshIndicatorKey.currentState?.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scooter = context.watch<ScooterService>();
    final phoneListAvailable =
        phoneKeyFeatureEnabled && scooter.connected && scooter.phoneKeyManagementSupported == true;
    final aliasAvailable = scooter.connected && scooter.keyAliasesSupported == true;
    if (_aliasScooterId != scooter.currentScooterId || _aliasAvailable != aliasAvailable) {
      if (_aliasScooterId != scooter.currentScooterId) {
        keycards = [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && scooter.connected) _loadKeycards();
        });
      }
      _aliasScooterId = scooter.currentScooterId;
      _aliasAvailable = aliasAvailable;
      _aliases = {};
      _masterCards = [];
      _aliasError = null;
      if (aliasAvailable) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadScooterAliases();
        });
      }
    }
    if (_phoneListScooterId != scooter.currentScooterId || _phoneListAvailable != phoneListAvailable) {
      _phoneListScooterId = scooter.currentScooterId;
      _phoneListAvailable = phoneListAvailable;
      _enrolledPhones = [];
      _phoneListError = null;
      if (phoneListAvailable) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadEnrolledPhones();
        });
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "ls_keycard_title")),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddKeycardDialog,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _loadKeycards,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: wideContentPadding(context, base: const EdgeInsets.only(top: 16, bottom: 32)),
          children: [
            if (phoneKeyFeatureEnabled)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Use this Android phone as a key', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('Set up a device-bound key, then tap your master card to enter learn mode. '
                        'Hold the unlocked phone against the scooter reader, and tap the master card again to save it. '
                        'The phone screen and NFC must be on for future taps.'),
                    const SizedBox(height: 8),
                    if (_phoneFingerprint != null) SelectableText('Phone key: $_phoneFingerprint'),
                    if (_phoneKeyError != null) Text(_phoneKeyError!, style: const TextStyle(color: Colors.red)),
                    TextButton(
                      onPressed: _creatingPhoneKey ? null : _setUpPhoneKey,
                      child: Text(_creatingPhoneKey ? 'Setting up…' : 'Set up / show phone key'),
                    ),
                  ]),
                ),
              ),
            if (phoneListAvailable)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(FlutterI18n.translate(context, 'ls_phone_enrolled_title'),
                        style: Theme.of(context).textTheme.titleMedium),
                    if (_loadingPhones)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      )
                    else if (_phoneListError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(FlutterI18n.translate(context, 'ls_phone_enrolled_load_error')),
                      )
                    else if (_enrolledPhones.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(FlutterI18n.translate(context, 'ls_phone_enrolled_empty')),
                      ),
                    for (final id in _enrolledPhones)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_aliases['phone:$id'] ??
                            FlutterI18n.translate(context, 'ls_phone_enrolled_entry',
                                translationParams: {'suffix': id.substring(id.length - 8)})),
                        subtitle: Text(id, overflow: TextOverflow.ellipsis),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (aliasAvailable)
                            IconButton(
                              tooltip: FlutterI18n.translate(context, 'ls_key_alias_rename'),
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _showCredentialRenameDialog('phone', id),
                            ),
                          IconButton(
                            tooltip: FlutterI18n.translate(context, 'ls_phone_remove_title'),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _removingPhone == null ? () => _confirmRemovePhone(id) : null,
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
            if (aliasAvailable && _loadingAliases)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: LinearProgressIndicator(),
              ),
            if (aliasAvailable && _aliasError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(FlutterI18n.translate(context, 'ls_key_alias_sync_error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (aliasAvailable && _masterCards.isNotEmpty)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(children: [
                  ListTile(title: Text(FlutterI18n.translate(context, 'ls_key_master_title'))),
                  for (final uid in _masterCards)
                    ListTile(
                      title: Text(_aliases['card:$uid'] ??
                          _localAliases[uid] ??
                          FlutterI18n.translate(context, 'ls_key_master_default')),
                      subtitle: Text(uid),
                      trailing: IconButton(
                        tooltip: FlutterI18n.translate(context, 'ls_key_alias_rename'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showCredentialRenameDialog('card', uid),
                      ),
                    ),
                ]),
              ),
            for (final (index, keycard) in keycards.indexed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: KeycardCard(
                  key: ValueKey(keycard),
                  index: index,
                  uid: keycard,
                  alias: _aliases['card:$keycard'] ?? _localAliases[keycard],
                  onlyCard: keycards.length == 1,
                  highlighted: _highlightedUid == keycard,
                  onDelete: _deleteKeycard,
                  onRename: _renameKeycard,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadKeycards() async {
    if (_isLoadingKeycards) {
      _reloadKeycardsAfterCurrent = true;
      return;
    }
    final service = context.read<ScooterService>();
    final scooterId = service.currentScooterId;

    setState(() {
      _isLoadingKeycards = true;
    });

    try {
      List<String> loadedKeycards = await service.actions.listKeycards();
      Logger('LsKeycardScreen').info('Loaded keycards: $loadedKeycards');
      if (!mounted || service.currentScooterId != scooterId) return;
      setState(() {
        keycards = loadedKeycards;
      });
      _startBackgroundNfcScan();
    } catch (e) {
      Logger('LsKeycardScreen').severe('Failed to load keycards: $e');
      if (!mounted || service.currentScooterId != scooterId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(FlutterI18n.translate(context, "ls_keycard_load_error", translationParams: {"error": e.toString()})),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingKeycards = false);
        if (_reloadKeycardsAfterCurrent) {
          _reloadKeycardsAfterCurrent = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadKeycards();
          });
        }
      }
    }
    await _loadEnrolledPhones();
    await _loadScooterAliases();
  }

  Future<void> _loadEnrolledPhones() async {
    if (!mounted || !phoneKeyFeatureEnabled) return;
    if (_loadingPhones) {
      _reloadPhonesAfterCurrent = true;
      return;
    }
    final service = context.read<ScooterService>();
    if (!service.connected || service.phoneKeyManagementSupported != true) {
      setState(() {
        _enrolledPhones = [];
        _phoneListError = null;
      });
      return;
    }
    final scooterId = service.currentScooterId;
    setState(() {
      _loadingPhones = true;
      _enrolledPhones = [];
      _phoneListError = null;
    });
    try {
      final phones = await service.actions.listPhoneKeys();
      if (!mounted || service.currentScooterId != scooterId) return;
      setState(() => _enrolledPhones = phones..sort());
    } catch (e) {
      if (!mounted || service.currentScooterId != scooterId) return;
      setState(() {
        _enrolledPhones = [];
        _phoneListError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loadingPhones = false);
        if (_reloadPhonesAfterCurrent) {
          _reloadPhonesAfterCurrent = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadEnrolledPhones();
          });
        }
      }
    }
  }

  Future<void> _confirmRemovePhone(String id) async {
    final service = context.read<ScooterService>();
    final scooterId = service.currentScooterId;
    final lastCredential = keycards.isEmpty && _enrolledPhones.length == 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(FlutterI18n.translate(dialogContext, 'ls_phone_remove_title')),
        content: Text(FlutterI18n.translate(
            dialogContext, lastCredential ? 'ls_phone_remove_last_confirm' : 'ls_phone_remove_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(FlutterI18n.translate(dialogContext, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(FlutterI18n.translate(dialogContext, 'ls_keycard_delete_button')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || service.currentScooterId != scooterId) return;
    setState(() => _removingPhone = id);
    try {
      await service.actions.deletePhoneKey(id, force: lastCredential);
      await _loadEnrolledPhones();
      await _loadScooterAliases();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(FlutterI18n.translate(context, 'ls_phone_remove_error', translationParams: {'error': e.toString()})),
      ));
    } finally {
      if (mounted) setState(() => _removingPhone = null);
    }
  }

  Future<void> _showRefreshIndicatorAndReload() async {
    final refreshIndicatorState = _refreshIndicatorKey.currentState;
    if (refreshIndicatorState != null) {
      await refreshIndicatorState.show();
      return;
    }
    await _loadKeycards();
  }

  @override
  void dispose() {
    _stopBackgroundNfcScan();
    super.dispose();
  }

  void _startBackgroundNfcScan() async {
    // Android reader mode prevents our HostApduService from handling a scooter
    // tap. Leave NFC card emulation available when a phone key is configured.
    if (!Platform.isAndroid || _phoneFingerprint != null || _creatingPhoneKey) return;
    if (_isBackgroundScanning) return;
    final availability = await FlutterNfcKit.nfcAvailability;
    if (availability != NFCAvailability.available || !mounted || _phoneFingerprint != null) return;
    setState(() => _isBackgroundScanning = true);
    // Poll in a loop so that each tap can be detected while the screen is open.
    while (_isBackgroundScanning && mounted) {
      try {
        final tag = await FlutterNfcKit.poll(
          androidPlatformSound: false,
          androidCheckNDEF: false,
        );
        await FlutterNfcKit.finish();
        final uid = extractKeycardUid(tag);
        if (uid != null && keycards.contains(uid)) {
          await HapticFeedback.lightImpact();
          if (!mounted) return;
          setState(() => _highlightedUid = uid);
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          setState(() => _highlightedUid = null);
        }
      } catch (_) {
        // Poll was cancelled (e.g. dialog opened) — stop the loop.
        break;
      }
    }
    if (mounted) setState(() => _isBackgroundScanning = false);
  }

  void _stopBackgroundNfcScan() {
    if (!_isBackgroundScanning) return;
    _isBackgroundScanning = false;
    FlutterNfcKit.finish().catchError((_) {});
    if (mounted) setState(() {});
  }

  void _showAddKeycardDialog() async {
    _stopBackgroundNfcScan();
    // Check NFC availability before showing the dialog
    final nfcAvailability = await FlutterNfcKit.nfcAvailability;
    if (!mounted) {
      _startBackgroundNfcScan();
      return;
    }
    if (nfcAvailability == NFCAvailability.not_supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FlutterI18n.translate(context, "ls_keycard_nfc_unavailable"))),
      );
      _startBackgroundNfcScan();
      return;
    } else if (nfcAvailability == NFCAvailability.disabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_keycard_nfc_disabled")),
        ),
      );
      _startBackgroundNfcScan();
      return;
    }

    // show the dialog and wait for a UID to be determined
    final String? uid = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => KeycardAddDialog(existingUids: keycards),
    );

    if (uid == null) {
      if (mounted && Platform.isIOS) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FlutterI18n.translate(context, "ls_keycard_ios_unsupported"))),
        );
      }
      _startBackgroundNfcScan();
      return;
    }
    if (!mounted) {
      _startBackgroundNfcScan();
      return;
    }

    // optimistically add the card to the list
    setState(() {
      keycards.add(uid);
    });

    // add it to the scooter
    try {
      await context.read<ScooterService>().actions.addKeycard(
            uid,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FlutterI18n.translate(context, "ls_keycard_add_success"))),
      );
    } catch (_) {
      // if it fails, remove the optimistically added card and show an error
      if (!mounted) return;
      setState(() {
        keycards.remove(uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FlutterI18n.translate(context, "ls_keycard_add_error"))),
      );
    } finally {
      // refresh the list to show the actual new list of keycards
      await _showRefreshIndicatorAndReload();
      _startBackgroundNfcScan();
    }
  }

  Future<void> _loadAliases() async {
    try {
      final raw = await SharedPreferencesAsync().getString('keycard_aliases');
      if (raw == null || !mounted) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      setState(() => _localAliases = decoded.map((k, v) => MapEntry(k, v as String)));
    } catch (e) {
      Logger('LsKeycardScreen').warning('Could not load local key names: $e');
    }
  }

  Future<void> _saveAliases() async {
    await SharedPreferencesAsync().setString('keycard_aliases', jsonEncode(_localAliases));
  }

  Future<void> _queueAliasOperation(Future<void> Function() action) {
    final next = _aliasQueue.then((_) => action());
    _aliasQueue = next.catchError((Object error, StackTrace stack) {
      Logger('LsKeycardScreen').warning('Key name operation failed: $error');
    });
    return next;
  }

  Future<void> _loadScooterAliases() => _queueAliasOperation(_fetchScooterAliases);

  Future<void> _fetchScooterAliases() async {
    if (!mounted) return;
    final service = context.read<ScooterService>();
    if (!service.connected || service.keyAliasesSupported != true) return;
    final scooterId = service.currentScooterId;
    setState(() => _loadingAliases = true);
    try {
      await _localAliasLoad;
      final masters = await service.actions.listMasterKeys();
      final names = await service.actions.listKeyAliases();
      if (!mounted || service.currentScooterId != scooterId || !service.connected) return;
      final plan = planKeyAliasImport([...keycards, ...masters], names, _localAliases);
      var importFailed = plan.invalidLocalNames;
      for (final entry in plan.names.entries) {
        try {
          await service.actions.setKeyAlias('card', entry.key, entry.value);
          if (!mounted || service.currentScooterId != scooterId || !service.connected) return;
          names['card:${entry.key}'] = entry.value;
        } catch (e) {
          importFailed = true;
          Logger('LsKeycardScreen').warning('Could not import local key name: $e');
        }
      }
      if (!mounted || service.currentScooterId != scooterId || !service.connected) return;
      setState(() {
        _aliases = names;
        _masterCards = masters;
        _aliasError = importFailed ? 'import' : null;
      });
    } catch (e) {
      if (!mounted || service.currentScooterId != scooterId) return;
      setState(() => _aliasError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingAliases = false);
    }
  }

  Future<void> _renameCredential(String kind, String id, String name) {
    final service = context.read<ScooterService>();
    final targetId = service.currentScooterId;
    return _queueAliasOperation(() async {
      if (!mounted || service.currentScooterId != targetId) return;
      await _performRenameCredential(kind, id, name);
    });
  }

  Future<void> _performRenameCredential(String kind, String id, String name) async {
    await _localAliasLoad;
    if (!mounted) return;
    final cleaned = name.trim();
    if (cleaned.isNotEmpty && checkKeyAlias(cleaned) != null) {
      _showAliasError('ls_key_alias_invalid');
      return;
    }
    final service = context.read<ScooterService>();
    final scooterId = service.currentScooterId;
    final synced = service.connected && service.keyAliasesSupported == true;
    if (kind == 'phone' && !synced) return;
    try {
      if (synced) {
        if (cleaned.isEmpty) {
          await service.actions.clearKeyAlias(kind, id);
        } else {
          await service.actions.setKeyAlias(kind, id, cleaned);
        }
        if (!mounted || service.currentScooterId != scooterId || !service.connected) return;
        setState(() {
          if (cleaned.isEmpty) {
            _aliases.remove('$kind:$id');
          } else {
            _aliases['$kind:$id'] = cleaned;
          }
        });
      }
      if (kind == 'card') {
        if (!mounted || (synced && service.currentScooterId != scooterId)) return;
        setState(() {
          if (cleaned.isEmpty) {
            _localAliases.remove(id);
          } else {
            _localAliases[id] = cleaned;
          }
        });
        await _saveAliases();
      }
    } catch (e) {
      Logger('LsKeycardScreen').warning('Could not save key name: $e');
      _showAliasError('ls_key_alias_save_error');
    }
  }

  void _showAliasError(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(FlutterI18n.translate(context, key))),
    );
  }

  Future<void> _renameKeycard(String uid, String alias) => _renameCredential('card', uid, alias);

  Future<void> _showCredentialRenameDialog(String kind, String id) async {
    final controller = TextEditingController(
      text: _aliases['$kind:$id'] ?? (kind == 'card' ? _localAliases[id] : null) ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(FlutterI18n.translate(dialogContext, 'ls_key_alias_rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxKeyAliasBytes,
          decoration: InputDecoration(hintText: FlutterI18n.translate(dialogContext, 'ls_keycard_alias_hint')),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(FlutterI18n.translate(dialogContext, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(FlutterI18n.translate(dialogContext, 'ls_keycard_save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && mounted) await _renameCredential(kind, id, name);
  }

  Future<void> _deleteKeycard(String uid) async {
    setState(() {
      keycards.remove(uid);
    });

    try {
      await context.read<ScooterService>().actions.deleteKeycard(
            uid,
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FlutterI18n.translate(context, "ls_keycard_delete_error")),
        ),
      );
    } finally {
      await _showRefreshIndicatorAndReload();
    }
  }
}

class KeycardCard extends StatefulWidget {
  final int index;
  final String uid;
  final String? alias;
  final bool onlyCard;
  final bool highlighted;
  final Future<void> Function(String uid) onDelete;
  final Future<void> Function(String uid, String alias) onRename;

  const KeycardCard({
    super.key,
    required this.index,
    required this.uid,
    required this.onDelete,
    required this.onRename,
    this.alias,
    this.onlyCard = false,
    this.highlighted = false,
  });

  @override
  State<KeycardCard> createState() => _KeycardCardState();
}

class _KeycardCardState extends State<KeycardCard> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 75),
    ]).animate(_animController);
  }

  @override
  void didUpdateWidget(KeycardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted && !oldWidget.highlighted) {
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
            ),
          ],
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          gradient: LinearGradient(
            colors: [
              HSLColor.fromColor(_getColorForIndex(widget.index)).withLightness(0.4).toColor(),
              HSLColor.fromColor(_getColorForIndex(widget.index)).withLightness(0.2).toColor(),
            ],
            begin: Alignment.topRight,
            end: Alignment.topLeft,
          ),
        ),
        height: MediaQuery.of(context).size.width * 0.55,
        child: child,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.contactless_outlined, size: 40, color: Colors.white),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: Colors.white,
                ),
                onSelected: (value) {
                  if (value == 'rename') _showRenameDialog(context);
                  if (value == 'delete') _confirmAndDeleteKeycard(context);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'rename', child: Text(FlutterI18n.translate(ctx, "nav_rename"))),
                  if (!widget.onlyCard)
                    PopupMenuItem(value: 'delete', child: Text(FlutterI18n.translate(ctx, "ls_keycard_delete_button"))),
                ],
              ),
            ],
          ),
          Spacer(),
          Text(
            // split the UID into groups of 4 characters to match the credit card style design
            List.generate(
                    (widget.uid.length / 4).ceil(),
                    (i) =>
                        widget.uid.substring(i * 4, (i + 1) * 4 > widget.uid.length ? widget.uid.length : (i + 1) * 4))
                .join(' '),
            style: const TextStyle(
              fontFamily: 'KodeMono',
              color: Colors.white,
              fontSize: 28,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            textDirection: TextDirection.rtl,
          ),
          SizedBox(height: 16),
          Text(
            widget.alias?.isNotEmpty == true
                ? widget.alias!
                : FlutterI18n.translate(context, "ls_keycard_default_name",
                    translationParams: {"number": (widget.index + 1).toString()}),
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
        ],
      ),
    );
  }

  Color _getColorForIndex(int index) {
    switch (index % 7) {
      case 0:
        return Color(0xFFFF554C);
      case 1:
        return Color(0xFF0395FF);
      case 2:
        return Color(0xFF245544);
      case 3:
        return Color(0xFF303030);
      case 4:
        return Colors.deepOrange.shade400;
      case 5:
        return Colors.teal.shade500;
      case 6:
        return Colors.deepPurple.shade400;
      default:
        return Colors.grey;
    }
  }

  void _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: widget.alias ?? '');
    final alias = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(FlutterI18n.translate(context, "ls_keycard_rename_title")),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: FlutterI18n.translate(context, "ls_keycard_alias_hint")),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(FlutterI18n.translate(context, "cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(FlutterI18n.translate(context, "ls_keycard_save")),
          ),
        ],
      ),
    );
    controller.dispose();
    if (alias != null) await widget.onRename(widget.uid, alias);
  }

  void _confirmAndDeleteKeycard(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(FlutterI18n.translate(context, "ls_keycard_delete_title")),
        content: Text(FlutterI18n.translate(context, "ls_keycard_delete_confirm")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(FlutterI18n.translate(context, "cancel")),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              foregroundColor: Theme.of(context).colorScheme.surface,
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              await widget.onDelete(widget.uid);
            },
            child: Text(FlutterI18n.translate(context, "ls_keycard_delete_button")),
          ),
        ],
      ),
    );
  }
}
