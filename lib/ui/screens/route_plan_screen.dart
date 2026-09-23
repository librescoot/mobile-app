import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:unustasis/domain/nav_destination.dart';
import 'package:unustasis/geo_helper.dart';
import 'package:unustasis/scooter_service.dart';
import '../widgets/header.dart';
import '../widgets/photon_autocomplete.dart';
import '../wide_layout.dart';

/// Editor for the scooter's multi-hop route plan. Edits go over BLE one stop
/// per command, capped at 100 bytes.
class RoutePlanScreen extends StatefulWidget {
  const RoutePlanScreen({super.key});

  @override
  State<RoutePlanScreen> createState() => _RoutePlanScreenState();
}

class _RoutePlanScreenState extends State<RoutePlanScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<NavDestination> _favorites = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final service = context.read<ScooterService>();
    if (!service.connected) {
      setState(() {
        _loading = false;
        _error = FlutterI18n.translate(context, 'nav_route_offline');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.refreshRoutePlan();
      final favorites = await service.routePlanFavorites();
      if (!mounted) return;
      setState(() {
        _favorites = favorites;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FlutterI18n.translate(context, 'nav_route_error', translationParams: {'error': error.toString()});
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FlutterI18n.translate(context, 'nav_error', translationParams: {'error': error.toString()})),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addStop() async {
    final destination = await showModalBottomSheet<NavDestination>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _StopPickerSheet(favorites: _favorites),
    );
    if (destination == null || !mounted) return;
    await _run(() => context.read<ScooterService>().addRouteStop(destination));
  }

  Future<void> _removeStop(int oneBasedIndex) async {
    await _run(() => context.read<ScooterService>().removeRouteStop(oneBasedIndex));
  }

  Future<void> _skipStop() async {
    await _run(() => context.read<ScooterService>().skipRouteStop());
  }

  Future<void> _clearPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(FlutterI18n.translate(context, 'nav_route_clear_title')),
        content: Text(FlutterI18n.translate(context, 'nav_route_clear_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(FlutterI18n.translate(context, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(FlutterI18n.translate(context, 'nav_route_clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => context.read<ScooterService>().clearRoutePlan());
  }

  Future<void> _reorder(List<NavDestination> stops, int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final ordered = List<NavDestination>.from(stops);
    ordered.insert(newIndex, ordered.removeAt(oldIndex));

    final service = context.read<ScooterService>();
    final active = service.routePlanStep > 0 || service.navigationActive == true;
    if (active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(FlutterI18n.translate(context, 'nav_route_reorder_title')),
          content: Text(FlutterI18n.translate(context, 'nav_route_reorder_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(FlutterI18n.translate(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(FlutterI18n.translate(context, 'nav_route_reorder')),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        // Rows come from the service; a rebuild restores them on cancel.
        if (mounted) setState(() {});
        return;
      }
    }
    if (!mounted) return;
    await _run(() => context.read<ScooterService>().reorderRoutePlan(ordered));
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final stops = service.routePlanStops;
    final step = service.routePlanStep;

    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'nav_route_title')),
        forceMaterialTransparency: true,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        scrolledUnderElevation: 0,
        actions: [
          if (stops.isNotEmpty)
            IconButton(
              tooltip: FlutterI18n.translate(context, 'nav_route_clear'),
              onPressed: _busy ? null : _clearPlan,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Stack(
        children: [
          _body(service, stops, step),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(ScooterService service, List<NavDestination> stops, int step) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && stops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _reload,
                child: Text(FlutterI18n.translate(context, 'nav_route_retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (stops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                FlutterI18n.translate(context, 'nav_route_empty_title'),
                style: const TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                FlutterI18n.translate(context, 'nav_route_empty_subtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _addStop,
                icon: const Icon(Icons.add),
                label: Text(FlutterI18n.translate(context, 'nav_route_add_stop')),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Header(
          FlutterI18n.translate(context, 'nav_route_stop_of', translationParams: {
            'current': '${step + 1}',
            'total': '${stops.length}',
          }),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: wideContentPadding(context, base: const EdgeInsets.fromLTRB(8, 8, 8, 8)),
            buildDefaultDragHandles: false,
            itemCount: stops.length,
            onReorderItem: (oldIndex, newIndex) => _reorder(stops, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final stop = stops[index];
              final label = stop.name?.isNotEmpty == true ? stop.name! : _formatCoordinates(stop);
              return Card(
                key: ValueKey('route-stop-$index-$label'),
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: _RouteStopMarker(
                    index: index,
                    count: stops.length,
                    currentStep: step,
                  ),
                  title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: stop.name?.isNotEmpty == true
                      ? Text(_formatCoordinates(stop), maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index == step)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            FlutterI18n.translate(context, 'nav_route_current'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: FlutterI18n.translate(context, 'nav_route_remove'),
                        onPressed: _busy ? null : () => _removeStop(index + 1),
                        icon: const Icon(Icons.close),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _addStop,
                    icon: const Icon(Icons.add),
                    label: Text(FlutterI18n.translate(context, 'nav_route_add_stop')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || step + 1 >= stops.length ? null : _skipStop,
                    icon: const Icon(Icons.skip_next),
                    label: Text(FlutterI18n.translate(context, 'nav_route_skip')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatCoordinates(NavDestination destination) => '${destination.location.latitude.toStringAsFixed(5)}, '
      '${destination.location.longitude.toStringAsFixed(5)}';
}

class _RouteStopMarker extends StatelessWidget {
  const _RouteStopMarker({
    required this.index,
    required this.count,
    required this.currentStep,
  });

  final int index;
  final int count;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = index == currentStep;
    final completed = index < currentStep;
    final lineColor = scheme.outlineVariant;
    final completedColor = scheme.primary;
    return SizedBox(
      key: ValueKey('route-stop-marker-$index'),
      width: 40,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (index > 0)
            Positioned(
              key: ValueKey('route-stop-line-before-$index'),
              top: -16,
              bottom: 28,
              child: Container(
                width: 3,
                color: index <= currentStep ? completedColor : lineColor,
              ),
            ),
          if (index + 1 < count)
            Positioned(
              key: ValueKey('route-stop-line-after-$index'),
              top: 28,
              bottom: -16,
              child: Container(
                width: 3,
                color: completed ? completedColor : lineColor,
              ),
            ),
          CircleAvatar(
            radius: 18,
            backgroundColor: current ? scheme.primary : scheme.surfaceContainerHighest,
            foregroundColor: current ? scheme.onPrimary : scheme.onSurfaceVariant,
            child: index + 1 == count
                ? const Icon(
                    Icons.flag_outlined,
                    key: ValueKey('route-destination-marker'),
                    size: 19,
                  )
                : Text('${index + 1}'),
          ),
        ],
      ),
    );
  }
}

/// Picks one stop: Photon search plus saved destinations.
class _StopPickerSheet extends StatelessWidget {
  const _StopPickerSheet({required this.favorites});

  final List<NavDestination> favorites;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Header(
                FlutterI18n.translate(context, 'nav_route_add_stop'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              ),
            ),
            PhotonAutocomplete(
              formatFeature: GeoHelper.fullNameFromFeature,
              onSelected: (feature) {
                Navigator.of(context).pop(NavDestination(
                  location: LatLng(feature.coordinates.latitude.toDouble(), feature.coordinates.longitude.toDouble()),
                  name: GeoHelper.nameFromFeature(feature),
                ));
              },
            ),
            if (favorites.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                FlutterI18n.translate(context, 'nav_route_saved_places'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: favorites.length,
                  itemBuilder: (context, index) {
                    final destination = favorites[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        destination.name ?? '${destination.location.latitude}, ${destination.location.longitude}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(destination),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
