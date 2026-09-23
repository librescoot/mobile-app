import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/trip_counter.dart';
import 'package:scooter_flutter/trip_commands.dart';

import '../../domain/saved_scooter.dart';
import '../../scooter_service.dart';
import '../widgets/header.dart';
import '../wide_layout.dart';

class TripCounterScreen extends StatefulWidget {
  const TripCounterScreen({super.key});

  @override
  State<TripCounterScreen> createState() => _TripCounterScreenState();
}

class _TripCounterScreenState extends State<TripCounterScreen> {
  Timer? _refreshTimer;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) _refresh();
      });
    });
  }

  Future<void> _refresh() async {
    final service = context.read<ScooterService>();
    service.refreshOdometer();
    try {
      if (service.tripCounterSupported == true) await service.refreshTripCounter();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String _reason(BuildContext context, TripResetReason reason) =>
      FlutterI18n.translate(context, 'trip_reason_${reason.name}');

  String _errorText(BuildContext context, Object error) {
    if (error is TimeoutException || error is TripResetException && error.failure == TripResetFailure.timeout) {
      return FlutterI18n.translate(context, 'trip_timeout');
    }
    if (error.toString().toLowerCase().contains('connected')) {
      return FlutterI18n.translate(context, 'trip_disconnected');
    }
    return FlutterI18n.translate(context, 'trip_error');
  }

  String _lastReset(BuildContext context, TripCounterSnapshot snapshot) {
    final reset = snapshot.lastReset;
    if (reset == null) return FlutterI18n.translate(context, 'trip_never');
    final dateTime = reset.dateTime?.toLocal();
    final when = dateTime == null
        ? reset.seconds.toString()
        : '${MaterialLocalizations.of(context).formatMediumDate(dateTime)} · '
            '${MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(dateTime),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          )}';
    return '$when · ${_reason(context, snapshot.lastResetReason)}';
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final saved = service.settingsTargetScooter;
    final liveTrip = service.tripCounter;
    final trip = liveTrip ?? saved?.cachedTripCounter;
    final odometer = service.odometerMeters ?? saved?.cachedOdometerMeters;
    final connected = service.connected;
    final supported = service.tripCounterSupported;
    final loading = service.tripCounterLoading;
    final hasData = trip != null || odometer != null;
    final scooterName = saved?.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'trip_title')),
        actions: [
          if (liveTrip != null && connected && supported == true)
            if (loading)
              const Padding(
                padding: EdgeInsets.all(15),
                child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                tooltip: FlutterI18n.translate(context, 'trip_retry'),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: wideContentPadding(
            context,
            base: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
          ),
          children: [
            if (!hasData && !connected)
              _StateMessage(
                icon: Icons.bluetooth_disabled,
                text: FlutterI18n.translate(context, 'trip_disconnected'),
                onRetry: _refresh,
              )
            else if (!hasData && supported == false)
              _StateMessage(icon: Icons.not_interested, text: FlutterI18n.translate(context, 'trip_unsupported'))
            else if (!hasData && loading)
              const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
            else if (!hasData && _error != null)
              _StateMessage(icon: Icons.error_outline, text: _errorText(context, _error!), onRetry: _refresh)
            else if (!hasData)
              _StateMessage(icon: Icons.pending_outlined, text: FlutterI18n.translate(context, 'trip_loading'))
            else ...[
              if (!connected)
                _InfoBanner(
                  icon: Icons.cloud_off_outlined,
                  text: FlutterI18n.translate(context, 'ride.cached_data'),
                ),
              if (_error != null) _ErrorBanner(text: _errorText(context, _error!), onRetry: _refresh),
              if (scooterName != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text(scooterName, style: Theme.of(context).textTheme.titleMedium)),
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: liveTrip != null && connected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        FlutterI18n.translate(
                          context,
                          liveTrip != null && connected ? 'ride.live' : 'ride.saved',
                        ),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              _RideOverview(odometerMeters: odometer, trip: trip),
              if (trip != null)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.history_outlined),
                  title: Text(FlutterI18n.translate(context, 'trip_last_reset')),
                  subtitle: Text(_lastReset(context, trip)),
                ),
              if (service.savedScooters.length > 1) ...[
                Header(FlutterI18n.translate(context, 'ride.all_scooters')),
                _FleetOverview(scooters: service.savedScooters.values.toList()),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

class _RideOverview extends StatelessWidget {
  const _RideOverview({required this.odometerMeters, required this.trip});

  final int? odometerMeters;
  final TripCounterSnapshot? trip;

  String _duration(int seconds) => '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tripDistance = trip == null ? '—' : '${(trip!.distanceMeters / 1000).toStringAsFixed(1)} km';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, size: 34, color: colors.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tripDistance, style: Theme.of(context).textTheme.headlineMedium),
                    Text(
                      FlutterI18n.translate(context, 'ride.current_trip'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (trip != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    icon: Icons.timer_outlined,
                    label: FlutterI18n.translate(context, 'trip_riding_time'),
                    value: _duration(trip!.ridingSeconds),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    icon: Icons.speed_outlined,
                    label: FlutterI18n.translate(context, 'trip_average_speed'),
                    value: '${trip!.averageSpeedKph.toStringAsFixed(1)} km/h',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.av_timer_outlined, color: colors.primary),
            title: Text(FlutterI18n.translate(context, 'ride.odometer')),
            trailing: Text(
              odometerMeters == null ? '—' : '${(odometerMeters! / 1000).toStringAsFixed(1)} km',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(child: Text(value, style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
}

class _FleetOverview extends StatelessWidget {
  const _FleetOverview({required this.scooters});

  final List<SavedScooter> scooters;

  @override
  Widget build(BuildContext context) {
    final withOdometer = scooters.where((scooter) => scooter.cachedOdometerMeters != null).toList()
      ..sort((a, b) => (b.cachedOdometerMeters ?? 0).compareTo(a.cachedOdometerMeters ?? 0));
    final totalMeters = withOdometer.fold<int>(0, (total, scooter) => total + scooter.cachedOdometerMeters!);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: EdgeInsets.zero,
        leading: const Icon(Icons.stacked_line_chart_outlined),
        title: Row(
          children: [
            Expanded(child: Text(FlutterI18n.translate(context, 'ride.total_odometer'))),
            Text(
              withOdometer.isEmpty ? '—' : '${(totalMeters / 1000).toStringAsFixed(1)} km',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        children: [
          for (final scooter in withOdometer)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 52, right: 16),
              leading: const Icon(Icons.av_timer_outlined),
              title: Text(scooter.name),
              trailing: Text('${(scooter.cachedOdometerMeters! / 1000).toStringAsFixed(1)} km'),
            ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        child: ListTile(leading: Icon(icon), title: Text(text)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(6),
        child: ListTile(
          leading: Icon(Icons.error_outline, color: colors.onErrorContainer),
          title: Text(text, style: TextStyle(color: colors.onErrorContainer)),
          trailing: IconButton(
            tooltip: FlutterI18n.translate(context, 'trip_retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            color: colors.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: text,
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Center(
            child: Column(
              children: [
                Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(text, textAlign: TextAlign.center),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(FlutterI18n.translate(context, 'trip_retry')),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
