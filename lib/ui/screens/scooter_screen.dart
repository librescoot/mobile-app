import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:unustasis/ui/screens/home_screen.dart';
import 'package:unustasis/ui/presentation/relative_time.dart';
import 'package:unustasis/ui/screens/onboarding_screen.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/ui/widgets/scooter_side_visual.dart';
import 'package:unustasis/geo_helper.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/ui/widgets/color_picker_dialog.dart';

/// Shared by the list screen and its cards.
final _log = Logger("ScooterSection");

enum ScooterTileStatus { disconnected, outOfRange, nearbyManual, nearbyAuto, waiting, connecting, connected }

class _ScooterStatusIndicator extends StatelessWidget {
  const _ScooterStatusIndicator(this.status);

  final ScooterTileStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (String label, Widget indicator) = switch (status) {
      ScooterTileStatus.connected => (
          FlutterI18n.translate(context, "state_name_unknown"),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 2),
            ),
          ),
        ),
      ScooterTileStatus.connecting => (
          FlutterI18n.translate(context, "state_name_linking"),
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: colors.tertiary),
          ),
        ),
      ScooterTileStatus.waiting => (
          FlutterI18n.translate(context, "stats_status_waiting"),
          Icon(Icons.low_priority_outlined, size: 20, color: colors.tertiary),
        ),
      ScooterTileStatus.nearbyManual => (
          FlutterI18n.translate(context, "stats_status_nearby_manual"),
          Icon(Icons.radar_outlined, size: 20, color: colors.primary),
        ),
      ScooterTileStatus.nearbyAuto => (
          FlutterI18n.translate(context, "stats_status_nearby_auto"),
          Icon(Icons.sync, size: 20, color: colors.primary),
        ),
      ScooterTileStatus.outOfRange => (
          FlutterI18n.translate(context, "stats_status_out_of_range"),
          Icon(Icons.sensors_off_outlined, size: 20, color: colors.onSurfaceVariant.withValues(alpha: 0.65)),
        ),
      ScooterTileStatus.disconnected => (
          FlutterI18n.translate(context, "state_name_disconnected"),
          Icon(Icons.radio_button_unchecked, size: 16, color: colors.onSurfaceVariant.withValues(alpha: 0.65)),
        ),
    };
    return Tooltip(
      message: label,
      child: Semantics(label: label, child: SizedBox.square(dimension: 24, child: Center(child: indicator))),
    );
  }
}

/// “1m ago”, or just the fresh-ping word when the ping is now.
String _lastSeenText(BuildContext context, SavedScooter savedScooter) {
  final short = savedScooter.lastPing.calculateExactTimeDifferenceInShort(context).toLowerCase();
  return short == FlutterI18n.translate(context, "stats_last_ping_now").toLowerCase() ? short : "$short ago";
}

class _ScooterActionsButton extends StatelessWidget {
  const _ScooterActionsButton({
    required this.savedScooter,
    required this.odometerMeters,
    required this.showAutoConnect,
    required this.rebuild,
    required this.onListChanged,
    required this.onRename,
    required this.onChangeColor,
  });

  final SavedScooter savedScooter;
  final int? odometerMeters;
  final bool showAutoConnect;
  final void Function() rebuild;
  final void Function() onListChanged;
  final Future<void> Function() onRename;
  final Future<void> Function() onChangeColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: IconButton.filledTonal(
        style: IconButton.styleFrom(
          backgroundColor: colors.surfaceContainerHighest,
          foregroundColor: colors.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        tooltip: FlutterI18n.translate(context, "stats_scooter_actions"),
        icon: const Icon(Icons.more_horiz, size: 22),
        onPressed: () => showScooterActionsSheet(
          context,
          savedScooter,
          odometerMeters,
          showAutoConnect: showAutoConnect,
          rebuild: rebuild,
          onListChanged: onListChanged,
          onRename: onRename,
          onChangeColor: onChangeColor,
        ),
      ),
    );
  }
}

Future<void> showScooterActionsSheet(
  BuildContext context,
  SavedScooter savedScooter,
  int? odometerMeters, {
  required bool showAutoConnect,
  required void Function() rebuild,
  required void Function() onListChanged,
  required Future<void> Function() onRename,
  required Future<void> Function() onChangeColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(savedScooter.name, style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(FlutterI18n.translate(context, "stats_scooter_id")),
            subtitle: Text(
              savedScooter.id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.av_timer_outlined),
            title: Text(
              odometerMeters != null
                  ? "${(odometerMeters / 1000).toStringAsFixed(1)} km"
                  : FlutterI18n.translate(context, "stats_unknown"),
            ),
          ),
          if (showAutoConnect)
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.sync),
              title: Text(FlutterI18n.translate(context, "stats_scooter_auto_connect")),
              subtitle: Text(
                FlutterI18n.translate(
                  context,
                  "stats_scooter_auto_connect_${savedScooter.autoConnect ? "on" : "off"}_description",
                ),
              ),
              value: savedScooter.autoConnect,
              onChanged: (value) {
                HapticFeedback.mediumImpact();
                savedScooter.autoConnect = value;
                rebuild();
                setSheetState(() {});
              },
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(FlutterI18n.translate(context, "stats_rename_scooter")),
            onTap: () async {
              Navigator.pop(sheetContext);
              await Future<void>.delayed(Duration.zero);
              await onRename();
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(FlutterI18n.translate(context, "settings_color")),
            onTap: () async {
              Navigator.pop(sheetContext);
              await Future<void>.delayed(Duration.zero);
              await onChangeColor();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            title: Text(
              FlutterI18n.translate(context, "settings_forget"),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              await Future<void>.delayed(Duration.zero);
              if (context.mounted) {
                await forgetScooter(context, savedScooter, onListChanged: onListChanged);
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// The forget dialog and removal, shared by both tile layouts.
Future<void> forgetScooter(BuildContext context, SavedScooter savedScooter,
    {required void Function() onListChanged}) async {
  bool? forget = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(FlutterI18n.translate(context, "forget_alert_title")),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text(FlutterI18n.translate(context, "forget_alert_body", translationParams: {"name": savedScooter.name})),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(FlutterI18n.translate(context, "forget_alert_cancel")),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text(FlutterI18n.translate(context, "forget_alert_confirm")),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );
  if (forget != true || !context.mounted) return;
  final String name = savedScooter.name;
  final message = FlutterI18n.translate(context, "forget_alert_success", translationParams: {"name": name});
  final service = context.read<ScooterService>();
  final id = savedScooter.id;
  await service.forgetSavedScooter(id);
  // A replacement/disposal can quietly supersede forgetting.
  if (!context.mounted || service.savedScooters.containsKey(id)) return;
  onListChanged();
  Fluttertoast.showToast(msg: message);
}

class ScooterScreen extends StatefulWidget {
  const ScooterScreen({
    super.key,
    this.onNavigateBack,
  });

  final VoidCallback? onNavigateBack;

  @override
  State<ScooterScreen> createState() => _ScooterScreenState();
}

class _ScooterScreenState extends State<ScooterScreen> {
  bool _isListView = false;

  /// Read once instead of per card build: the cards used to sit inside a
  /// FutureBuilder that wrapped their whole body.
  bool _showColorOnboarding = false;
  bool _aprilFools = false;
  int color = 1;
  String? nameCache;
  TextEditingController nameController = TextEditingController();
  FocusNode nameFocusNode = FocusNode();
  Timer? _odometerRefreshTimer;

  void setupInitialColor() async {
    int initialColor = await SharedPreferencesAsync().getInt("color") ?? 1;
    setState(() {
      color = initialColor;
    });
  }

  @override
  void initState() {
    super.initState();
    setupInitialColor();
    _loadViewMode();
    _loadCardFlags();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOdometer();
      _refreshPresence();
      _odometerRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _refreshOdometer();
        _refreshPresence();
        // Ordering and the relative "last seen" labels no longer follow every
        // telemetry notification, so refresh them on this cadence instead.
        if (mounted && ModalRoute.of(context)?.isCurrent == true) setState(() {});
      });
    });
  }

  /// Odometer is read-only and refreshed only while this screen is on top.
  void _refreshOdometer() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    context.read<ScooterService>().refreshOdometer();
  }

  void _refreshPresence() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    unawaited(context.read<ScooterService>().refreshScooterPresence());
  }

  Future<void> _loadCardFlags() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showColorOnboarding = prefs.getBool("color_onboarded") != true;
      _aprilFools = prefs.getBool("seasonal") == true && DateTime.now().month == 4 && DateTime.now().day == 1;
    });
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isListView = prefs.getBool('scooter_list_view_mode') ?? false;
    });
  }

  Future<void> _toggleViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isListView = !_isListView;
    });
    await prefs.setBool('scooter_list_view_mode', _isListView);
  }

  Future<void> _handleAddScooter(BuildContext context) async {
    final service = context.read<ScooterService>();
    service.disconnectAndClearDevice();

    List<String> savedIds = await service.getSavedScooterIds();
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (context) {
          return OnboardingScreen(
            excludedScooterIds: savedIds,
            skipWelcome: true,
          );
        },
      ));
    }
  }

  List<SavedScooter> sortedScooters(ScooterService service) {
    List<SavedScooter> scooters = service.savedScooters.values.toList();
    scooters.sort((a, b) {
      // Check if either scooter is the connected one
      if (a.id == service.currentScooterId) {
        return -1;
      }
      if (b.id == service.currentScooterId) {
        return 1;
      }

      // If neither is the connected scooter, sort by lastPing
      return b.lastPing.compareTo(a.lastPing);
    });
    return scooters;
  }

  /// What the screen itself depends on: which scooters exist, which one the
  /// service is on, and whether a connection attempt is in flight. Everything
  /// else - ping times, battery, odometer, state text - belongs to the cards,
  /// which subscribe for themselves. Watching the whole service here rebuilt
  /// every card several times a second while riding.
  String _listSignature(ScooterService service) => [
        for (final scooter in sortedScooters(service)) scooter.id,
        service.currentScooterId ?? '',
        service.state?.name ?? '',
        service.connectingScooterId ?? '',
        service.connected ? 'connected' : 'disconnected',
        service.selectedScooterId ?? '',
        service.scooterPresenceKnown ? 'presence-known' : 'presence-unknown',
        ...service.scootersInRange.toList()..sort(),
        service.autoConnectPriorityId ?? '',
      ].join('|');

  ScooterTileStatus _statusFor(ScooterService service, SavedScooter scooter) {
    if (service.connected && service.currentScooterId == scooter.id) {
      return ScooterTileStatus.connected;
    }
    if (service.connectingScooterId == scooter.id ||
        (service.currentScooterId == scooter.id && service.state == ScooterState.linking)) {
      return ScooterTileStatus.connecting;
    }
    if (service.scootersInRange.contains(scooter.id)) {
      if (!scooter.autoConnect) return ScooterTileStatus.nearbyManual;
      if (service.autoConnectPriorityId != null && service.autoConnectPriorityId != scooter.id) {
        return ScooterTileStatus.waiting;
      }
      return ScooterTileStatus.nearbyAuto;
    }
    return service.scooterPresenceKnown ? ScooterTileStatus.outOfRange : ScooterTileStatus.disconnected;
  }

  @override
  Widget build(BuildContext context) {
    context.select<ScooterService, String>(_listSignature);
    final scooterService = context.read<ScooterService>();
    final scooters = sortedScooters(scooterService);
    final bool single = scooters.length == 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title_scooter')),
        actions: [
          Selector<ScooterService, int>(
            selector: (context, service) => service.savedScooters.length,
            builder: (context, scooterCount, child) {
              if (scooterCount > 1) {
                return IconButton(
                  icon: Icon(_isListView ? Icons.grid_view : Icons.list),
                  onPressed: _toggleViewMode,
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _handleAddScooter(context),
          ),
        ],
      ),
      // Built lazily and keyed per scooter, so reordering (the connected
      // scooter is pinned first) reuses elements instead of remounting every
      // card and re-decoding its art.
      body: ListView.builder(
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        itemCount: scooters.length + 1,
        itemBuilder: (context, index) {
          if (index == scooters.length) return _addScooterButton(context);
          final scooter = scooters[index];
          final status = _statusFor(scooterService, scooter);
          final selected = scooterService.selectedScooterId == scooter.id;
          return KeyedSubtree(
            key: ValueKey(scooter.id),
            child: Padding(
              padding: _isListView
                  ? const EdgeInsets.symmetric(vertical: 4, horizontal: 16)
                  : const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: _isListView
                  ? SavedScooterListItem(
                      savedScooter: scooter,
                      single: single,
                      status: status,
                      selected: selected,
                      onListChanged: () => setState(() {}),
                      onNavigateBack: widget.onNavigateBack,
                    )
                  : SavedScooterCard(
                      savedScooter: scooter,
                      single: single,
                      status: status,
                      selected: selected,
                      showOnboarding: _showColorOnboarding,
                      forceHover: _aprilFools,
                      onListChanged: () => setState(() {}),
                      onNavigateBack: widget.onNavigateBack,
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _addScooterButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          backgroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        onPressed: () => _handleAddScooter(context),
        icon: Icon(
          Icons.add,
          color: Theme.of(context).colorScheme.surface,
          size: 16,
        ),
        label: Text(
          FlutterI18n.translate(context, "settings_add_scooter").toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _odometerRefreshTimer?.cancel();
    nameController.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }
}

class SavedScooterCard extends StatefulWidget {
  const SavedScooterCard({
    super.key,
    required this.savedScooter,
    required this.status,
    required this.selected,
    required this.single,
    required this.showOnboarding,
    required this.forceHover,
    required this.onListChanged,
    this.onNavigateBack,
  });

  final SavedScooter savedScooter;
  final ScooterTileStatus status;
  final bool selected;
  final bool single;
  final bool showOnboarding;
  final bool forceHover;

  /// Rebuilds the list, for the actions that change which rows exist or which
  /// one is connected. Everything else rebuilds this card alone.
  final void Function() onListChanged;
  final VoidCallback? onNavigateBack;

  @override
  State<SavedScooterCard> createState() => _SavedScooterCardState();
}

class _SavedScooterCardState extends State<SavedScooterCard> {
  late bool _showOnboarding = widget.showOnboarding;
  bool _dismissedOnboarding = false;
  Future<String?>? _addressFuture;

  /// Resolved once per stored location: a rebuild must not start a second
  /// lookup, and every rebuild used to allocate a new future.
  Future<String?> get _address => _addressFuture ??= GeoHelper.getScooterAddress(widget.savedScooter);

  @override
  void didUpdateWidget(covariant SavedScooterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The screen reads the pref asynchronously, so the flag can arrive after
    // the first build. A hint the user dismissed stays dismissed.
    if (!_dismissedOnboarding && widget.showOnboarding != oldWidget.showOnboarding) {
      _showOnboarding = widget.showOnboarding;
    }
    final before = oldWidget.savedScooter;
    final now = widget.savedScooter;
    if (before.lastAddress != now.lastAddress ||
        before.lastLocation?.latitude != now.lastLocation?.latitude ||
        before.lastLocation?.longitude != now.lastLocation?.longitude) {
      _addressFuture = null;
    }
  }

  void _hideOnboardingHint() {
    _dismissedOnboarding = true;
    SharedPreferences.getInstance().then((prefs) => prefs.setBool("color_onboarded", true));
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) => _SavedScooterCardBody(
        savedScooter: widget.savedScooter,
        status: widget.status,
        selected: widget.selected,
        single: widget.single,
        showOnboarding: _showOnboarding,
        forceHover: widget.forceHover,
        address: () => _address,
        hideOnboardingHint: _hideOnboardingHint,
        rebuild: () => setState(() {}),
        onListChanged: widget.onListChanged,
        onNavigateBack: widget.onNavigateBack,
      );
}

class _SavedScooterCardBody extends StatelessWidget {
  final SavedScooter savedScooter;
  final ScooterTileStatus status;
  final bool selected;
  final bool single;
  final bool showOnboarding;
  final bool forceHover;
  final Future<String?> Function() address;
  final void Function() hideOnboardingHint;
  final void Function() rebuild;
  final void Function() onListChanged;
  final VoidCallback? onNavigateBack;

  const _SavedScooterCardBody({
    required this.savedScooter,
    required this.status,
    required this.selected,
    required this.single,
    required this.showOnboarding,
    required this.forceHover,
    required this.address,
    required this.hideOnboardingHint,
    required this.rebuild,
    required this.onListChanged,
    this.onNavigateBack,
  });

  void setColor(int newColor, BuildContext context) async {
    savedScooter.color = newColor;
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    await prefs.setInt("color", newColor);
    if (context.mounted) context.read<ScooterService>().scooterColor = newColor;
  }

  Future<void> _changeColor(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final newColor = await showColorDialog(savedScooter.color, savedScooter.name, context);
    if (newColor != null && context.mounted) {
      setColor(newColor, context);
      rebuild();
    }
    if (showOnboarding) hideOnboardingHint();
  }

  Future<void> _rename(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final newName = await showRenameDialog(savedScooter.name, context);
    if (newName != null && newName.isNotEmpty && newName != savedScooter.name && context.mounted) {
      context.read<ScooterService>().renameSavedScooter(name: newName, id: savedScooter.id);
      rebuild();
    }
  }

  /// Forgets this scooter, waiting for the removal to land before rebuilding.
  Future<void> _forget(BuildContext context) => forgetScooter(context, savedScooter, onListChanged: onListChanged);

  Future<void> _connect(BuildContext context) async {
    try {
      _log.info("Trying to connect to ${savedScooter.id}");
      final service = context.read<ScooterService>();
      final attempt = service.connectToScooterId(savedScooter.id);
      service.startAutoRestart(targetScooterId: savedScooter.id);
      onListChanged();
      WidgetsBinding.instance.addPostFrameCallback((_) => onNavigateBack?.call());
      await attempt;
    } catch (e, stack) {
      _log.severe("Couldn't connect to ${savedScooter.id}", e, stack);
      if (context.mounted) {
        Fluttertoast.showToast(
          msg: FlutterI18n.translate(
            context,
            "settings_connect_failed",
            translationParams: {"name": savedScooter.name},
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = status == ScooterTileStatus.connected;
    final connecting = status == ScooterTileStatus.connecting;
    final liveOdometer = connected ? context.select<ScooterService, int?>((service) => service.odometerMeters) : null;
    final odometerMeters = liveOdometer ?? savedScooter.cachedOdometerMeters;
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: connecting
          ? null
          : connected
              ? () {
                  final service = context.read<ScooterService>();
                  service.stopAutoRestart();
                  service.disconnectAndClearDevice();
                  onListChanged();
                }
              : () => _connect(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          color: selected ? colors.surfaceContainerHigh : colors.surfaceContainer,
          border: selected ? Border.all(color: colors.primary.withValues(alpha: 0.3)) : null,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 208,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onLongPress: () => _changeColor(context),
                      child: Center(
                        child: SizedBox(
                          width: 264,
                          height: 160,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ScooterSideVisual(
                                imagePath: "images/scooter/side_${forceHover ? 9 : savedScooter.color}.webp",
                                height: 160,
                                backdropDiameter: 264,
                              ),
                              if (savedScooter.isLibrescoot == true)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Image.asset(
                                    "assets/icons/librescoot-flame.png",
                                    width: 26,
                                    height: 36,
                                    cacheWidth: (26 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(child: _ScooterStatusIndicator(status)),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _ScooterActionsButton(
                      savedScooter: savedScooter,
                      odometerMeters: odometerMeters,
                      showAutoConnect: !single,
                      rebuild: rebuild,
                      onListChanged: onListChanged,
                      onRename: () => _rename(context),
                      onChangeColor: () => _changeColor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (showOnboarding)
              Text(
                FlutterI18n.translate(context, "settings_color_onboarding"),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    savedScooter.name,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(height: 1.1),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 28,
              child: connecting
                  ? Text(
                      FlutterI18n.translate(context, "state_name_linking"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    )
                  : connected
                      ? Text(
                          context
                                  .select<ScooterService, ScooterState?>((service) => service.state)
                                  ?.description(context) ??
                              FlutterI18n.translate(context, "stats_unknown"),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        )
                      : null,
            ),
            if (connected &&
                context
                    .select<ScooterService, bool>((service) => service.identity.bluetoothTableOutOfDate == true)) ...[
              const SizedBox(height: 12),
              _StaleBluetoothProfileCard(onForget: () => _forget(context)),
            ],
            SizedBox(height: 8),
            BatteryBars(
              primarySOC: savedScooter.lastPrimarySOC,
              secondarySOC: savedScooter.lastSecondarySOC,
              dataIsOld: savedScooter.dataIsOld,
            ),
            ...[
              const SizedBox(height: 24),
              Divider(
                indent: 16,
                endIndent: 16,
                height: 0,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (savedScooter.lastLocation != null) ...[
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            MapsLauncher.launchCoordinates(
                              savedScooter.lastLocation!.latitude,
                              savedScooter.lastLocation!.longitude,
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.place_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: FutureBuilder<String?>(
                                  future: address(),
                                  builder: (context, snapshot) => Text(
                                    snapshot.hasData
                                        ? snapshot.data!
                                        : FlutterI18n.translate(context, "stats_no_location"),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Icon(Icons.schedule_outlined,
                        size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      _lastSeenText(context, savedScooter),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<String?> showRenameDialog(String initialValue, BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController textController = TextEditingController(text: initialValue);
        FocusNode textFieldNode = FocusNode();

        Future.delayed(const Duration(milliseconds: 100), () {
          if (context.mounted) {
            FocusScope.of(context).requestFocus(textFieldNode);
          }
        });

        return AlertDialog(
          title: Text(FlutterI18n.translate(context, "stats_name")),
          content: TextField(
            controller: textController,
            focusNode: textFieldNode,
          ),
          actions: [
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_cancel")),
              onPressed: () {
                Navigator.of(context).pop(); // Close without returning data
              },
            ),
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_save")),
              onPressed: () {
                Navigator.of(context).pop(textController.text); // Return the text
              },
            ),
          ],
        );
      },
    );
  }
}

class SavedScooterListItem extends StatefulWidget {
  const SavedScooterListItem({
    super.key,
    required this.savedScooter,
    required this.status,
    required this.selected,
    required this.single,
    required this.onListChanged,
    this.onNavigateBack,
  });

  final SavedScooter savedScooter;
  final ScooterTileStatus status;
  final bool selected;
  final bool single;
  final void Function() onListChanged;
  final VoidCallback? onNavigateBack;

  @override
  State<SavedScooterListItem> createState() => _SavedScooterListItemState();
}

class _SavedScooterListItemState extends State<SavedScooterListItem> {
  Future<String?>? _addressFuture;

  Future<String?> get _address => _addressFuture ??= GeoHelper.getScooterAddress(widget.savedScooter);

  @override
  void didUpdateWidget(covariant SavedScooterListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.savedScooter;
    final now = widget.savedScooter;
    if (before.lastAddress != now.lastAddress ||
        before.lastLocation?.latitude != now.lastLocation?.latitude ||
        before.lastLocation?.longitude != now.lastLocation?.longitude) {
      _addressFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) => _SavedScooterListItemBody(
        savedScooter: widget.savedScooter,
        status: widget.status,
        selected: widget.selected,
        single: widget.single,
        address: () => _address,
        rebuild: () => setState(() {}),
        onListChanged: widget.onListChanged,
        onNavigateBack: widget.onNavigateBack,
      );
}

class _SavedScooterListItemBody extends StatelessWidget {
  final SavedScooter savedScooter;
  final ScooterTileStatus status;
  final bool selected;
  final bool single;
  final Future<String?> Function() address;
  final void Function() rebuild;
  final void Function() onListChanged;
  final VoidCallback? onNavigateBack;

  const _SavedScooterListItemBody({
    required this.savedScooter,
    required this.status,
    required this.selected,
    required this.single,
    required this.address,
    required this.rebuild,
    required this.onListChanged,
    this.onNavigateBack,
  });

  @override
  Widget build(BuildContext context) {
    final connected = status == ScooterTileStatus.connected;
    final connecting = status == ScooterTileStatus.connecting;
    final liveOdometer = connected ? context.select<ScooterService, int?>((service) => service.odometerMeters) : null;
    final odometerMeters = liveOdometer ?? savedScooter.cachedOdometerMeters;
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: connecting
          ? null
          : connected
              ? () {
                  final service = context.read<ScooterService>();
                  service.stopAutoRestart();
                  service.disconnectAndClearDevice();
                  onListChanged();
                }
              : () async {
                  try {
                    _log.info("Trying to connect to ${savedScooter.id}");

                    final service = context.read<ScooterService>();
                    final attempt = service.connectToScooterId(savedScooter.id);
                    service.startAutoRestart(targetScooterId: savedScooter.id);
                    onListChanged();
                    // Show the selected scooter on the main screen while its
                    // connection continues; this callback still awaits the Future
                    // below so failures are handled rather than becoming unhandled.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      onNavigateBack?.call();
                    });
                    await attempt;
                  } catch (e, stack) {
                    _log.severe("Couldn't connect to ${savedScooter.id}", e, stack);
                    if (context.mounted) {
                      Fluttertoast.showToast(
                          msg: FlutterI18n.translate(context, "settings_connect_failed",
                              translationParams: {"name": savedScooter.name}));
                    }
                  }
                },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          color: selected ? colors.surfaceContainerHigh : colors.surfaceContainer,
          border: selected ? Border.all(color: colors.primary.withValues(alpha: 0.3)) : null,
        ),
        child: Column(
          children: [
            // First row: Scooter image and name
            Row(
              children: [
                // Scooter image - half the current size with connection indicator
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onLongPress: () => _changeColor(context),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.25,
                      child: Stack(
                        children: [
                          ScooterSideVisual(
                            imagePath: "images/scooter/side_${savedScooter.color}.webp",
                            height: MediaQuery.of(context).size.width * 0.16,
                          ),
                          if (savedScooter.isLibrescoot == true)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Image.asset(
                                "assets/icons/librescoot-flame.png",
                                width: 18,
                                height: 25,
                                cacheWidth: (18 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Name, telemetry, and actions
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _ScooterStatusIndicator(status),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    savedScooter.name,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.1),
                                  ),
                                ),
                              ],
                            ),
                            if (connecting)
                              Padding(
                                padding: const EdgeInsets.only(top: 2, bottom: 2),
                                child: Text(
                                  FlutterI18n.translate(context, "state_name_linking"),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            else if (connected)
                              Padding(
                                padding: const EdgeInsets.only(top: 2, bottom: 2),
                                child: Text(
                                  context
                                          .select<ScooterService, ScooterState?>((service) => service.state)
                                          ?.description(context) ??
                                      FlutterI18n.translate(context, "stats_unknown"),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            if (savedScooter.lastPrimarySOC != null || savedScooter.lastSecondarySOC != null)
                              BatteryBars(
                                primarySOC: savedScooter.lastPrimarySOC,
                                secondarySOC: savedScooter.lastSecondarySOC,
                                dataIsOld: savedScooter.dataIsOld,
                                compact: true,
                                alignment: WrapAlignment.start,
                              ),
                            if (!connected && !connecting) ...[
                              if (savedScooter.lastLocation != null) ...[
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () {
                                    MapsLauncher.launchCoordinates(
                                      savedScooter.lastLocation!.latitude,
                                      savedScooter.lastLocation!.longitude,
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      Icon(Icons.place_outlined,
                                          size: 14, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: FutureBuilder<String?>(
                                          future: address(),
                                          builder: (context, snapshot) => Text(
                                            snapshot.hasData
                                                ? snapshot.data!
                                                : FlutterI18n.translate(context, "stats_no_location"),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.schedule_outlined,
                                      size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                                  const SizedBox(width: 4),
                                  Text(
                                    _lastSeenText(context, savedScooter),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ScooterActionsButton(
                        savedScooter: savedScooter,
                        odometerMeters: odometerMeters,
                        showAutoConnect: !single,
                        rebuild: rebuild,
                        onListChanged: onListChanged,
                        onRename: () => _rename(context),
                        onChangeColor: () => _changeColor(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void setColor(int newColor, BuildContext context) async {
    savedScooter.color = newColor;
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    await prefs.setInt("color", newColor);
    if (context.mounted) context.read<ScooterService>().scooterColor = newColor;
  }

  Future<void> _changeColor(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final newColor = await showColorDialog(savedScooter.color, savedScooter.name, context);
    if (newColor != null && context.mounted) {
      setColor(newColor, context);
      rebuild();
    }
  }

  Future<void> _rename(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final newName = await showRenameDialog(savedScooter.name, context);
    if (newName != null && newName.isNotEmpty && newName != savedScooter.name && context.mounted) {
      context.read<ScooterService>().renameSavedScooter(name: newName, id: savedScooter.id);
      rebuild();
    }
  }

  Future<String?> showRenameDialog(String initialValue, BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController textController = TextEditingController(text: initialValue);
        FocusNode textFieldNode = FocusNode();

        Future.delayed(const Duration(milliseconds: 100), () {
          if (context.mounted) {
            FocusScope.of(context).requestFocus(textFieldNode);
          }
        });

        return AlertDialog(
          title: Text(FlutterI18n.translate(context, "stats_name")),
          content: TextField(
            controller: textController,
            focusNode: textFieldNode,
          ),
          actions: [
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_cancel")),
              onPressed: () {
                Navigator.of(context).pop(); // Close without returning data
              },
            ),
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_save")),
              onPressed: () {
                Navigator.of(context).pop(textController.text); // Return the text
              },
            ),
          ],
        );
      },
    );
  }
}

/// Shown when the phone is still using the GATT table it cached at pairing, so
/// un-pairing is the only fix.
class _StaleBluetoothProfileCard extends StatelessWidget {
  const _StaleBluetoothProfileCard({required this.onForget});

  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth_disabled_outlined, size: 20, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    FlutterI18n.translate(context, "ls_stale_bluetooth_title"),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              FlutterI18n.translate(context, "ls_stale_bluetooth_body"),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: onForget,
                child: Text(FlutterI18n.translate(context, "ls_stale_bluetooth_action")),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
