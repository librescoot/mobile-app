import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:scooter_core/trip_counter.dart';
import 'package:scooter_core/trip_expunge.dart';
import 'package:scooter_flutter/trip_commands.dart';

import '../../scooter_service.dart';

class TripCounterScreen extends StatefulWidget {
  const TripCounterScreen({super.key});

  @override
  State<TripCounterScreen> createState() => _TripCounterScreenState();
}

class _TripCounterScreenState extends State<TripCounterScreen> {
  Timer? _refreshTimer;
  Object? _error;
  final _retentionValue = TextEditingController();
  TripExpunge? _shownExpunge;
  TripExpungePolicy? _retentionPolicy;
  String? _retentionValidation;

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
    try {
      await Future.wait([service.refreshTripCounter(), service.refreshTripExpunge()]);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _setPolicy(TripResetPolicy policy) async {
    final service = context.read<ScooterService>();
    try {
      await service.setTripCounterResetPolicy(policy);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      // Re-read restores the scooter's actual policy after a rejected write.
      await _refresh();
      if (mounted) setState(() => _error = error);
    }
  }

  void _syncRetention(TripExpunge expunge) {
    if (_shownExpunge == expunge) return;
    _shownExpunge = expunge;
    _retentionPolicy = expunge.policy;
    _retentionValue.text = expunge.value ?? '';
    _retentionValidation = null;
  }

  Future<void> _setRetention() async {
    final policy = _retentionPolicy;
    if (policy == null) return;
    TripExpunge retention;
    try {
      retention = TripExpunge(policy, policy == TripExpungePolicy.never ? null : _retentionValue.text);
    } on FormatException {
      setState(() => _retentionValidation =
          policy == TripExpungePolicy.age ? 'trip_retention_invalid_age' : 'trip_retention_invalid_number');
      return;
    }
    final service = context.read<ScooterService>();
    try {
      await service.setTripExpunge(retention);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      await _refresh();
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(FlutterI18n.translate(dialogContext, 'trip_reset_confirm_title')),
        content: Text(FlutterI18n.translate(dialogContext, 'trip_reset_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(FlutterI18n.translate(dialogContext, 'trip_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(FlutterI18n.translate(dialogContext, 'trip_reset_now')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<ScooterService>().resetTripCounter();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String _policy(BuildContext context, TripResetPolicy policy) =>
      FlutterI18n.translate(context, 'trip_policy_${policy.wireName}');

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

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ScooterService>();
    final supported = service.tripCounterSupported;
    final snapshot = service.tripCounter;
    final loading = service.tripCounterLoading;
    final expunge = service.tripExpunge;
    final expungeSupported = service.tripExpungeSupported;
    final expungeLoading = service.tripExpungeLoading;
    final connected = service.connected;
    if (expunge != null) _syncRetention(expunge);
    return Scaffold(
      appBar: AppBar(title: Text(FlutterI18n.translate(context, 'trip_title'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (!connected)
              _StateMessage(icon: Icons.bluetooth_disabled, text: FlutterI18n.translate(context, 'trip_disconnected'))
            else if (supported == false)
              _StateMessage(icon: Icons.not_interested, text: FlutterI18n.translate(context, 'trip_unsupported'))
            else if (snapshot == null && loading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (snapshot == null && _error != null)
              _StateMessage(icon: Icons.error_outline, text: _errorText(context, _error!))
            else if (snapshot == null)
              _StateMessage(icon: Icons.pending_outlined, text: FlutterI18n.translate(context, 'trip_loading'))
            else ...[
              _Metric(
                  label: FlutterI18n.translate(context, 'trip_distance'),
                  value: '${(snapshot.distanceMeters / 1000).toStringAsFixed(1)} km'),
              _Metric(
                  label: FlutterI18n.translate(context, 'trip_riding_time'), value: _duration(snapshot.ridingSeconds)),
              _Metric(
                  label: FlutterI18n.translate(context, 'trip_average_speed'),
                  value: '${snapshot.averageSpeedKph.toStringAsFixed(1)} km/h'),
              const SizedBox(height: 20),
              Text(FlutterI18n.translate(context, 'trip_reset_policy'), style: Theme.of(context).textTheme.titleMedium),
              Semantics(
                label: FlutterI18n.translate(context, 'trip_reset_policy'),
                child: DropdownButton<TripResetPolicy>(
                  isExpanded: true,
                  value: snapshot.resetPolicy,
                  onChanged: loading
                      ? null
                      : (policy) {
                          if (policy != null) _setPolicy(policy);
                        },
                  items: TripResetPolicy.values
                      .map((policy) => DropdownMenuItem(value: policy, child: Text(_policy(context, policy))))
                      .toList(),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(FlutterI18n.translate(context, 'trip_last_reset')),
                subtitle: Text(snapshot.lastReset == null
                    ? FlutterI18n.translate(context, 'trip_never')
                    : '${snapshot.lastReset!.dateTime?.toLocal() ?? snapshot.lastReset!.seconds} — '
                        '${_reason(context, snapshot.lastResetReason)}'),
              ),
              const SizedBox(height: 20),
              Text(FlutterI18n.translate(context, 'trip_retention_title'),
                  style: Theme.of(context).textTheme.titleMedium),
              if (expungeSupported == false)
                _StateMessage(
                    icon: Icons.history_toggle_off, text: FlutterI18n.translate(context, 'trip_retention_unsupported'))
              else if (expunge != null) ...[
                Semantics(
                  label: FlutterI18n.translate(context, 'trip_retention_policy'),
                  child: DropdownButton<TripExpungePolicy>(
                    isExpanded: true,
                    value: _retentionPolicy,
                    onChanged: expungeLoading
                        ? null
                        : (policy) {
                            if (policy == null) return;
                            setState(() {
                              _retentionPolicy = policy;
                              _retentionValidation = null;
                              if (policy == TripExpungePolicy.age && _retentionValue.text.isEmpty) {
                                _retentionValue.text = '1d';
                              } else if (policy != TripExpungePolicy.never && _retentionValue.text.isEmpty) {
                                _retentionValue.text = '0';
                              }
                            });
                          },
                    items: TripExpungePolicy.values
                        .map((policy) => DropdownMenuItem(
                            value: policy,
                            child: Text(FlutterI18n.translate(context, 'trip_retention_policy_${policy.name}'))))
                        .toList(),
                  ),
                ),
                if (_retentionPolicy != TripExpungePolicy.never)
                  Semantics(
                    textField: true,
                    label: FlutterI18n.translate(
                        context,
                        _retentionPolicy == TripExpungePolicy.age
                            ? 'trip_retention_value_age'
                            : _retentionPolicy == TripExpungePolicy.count
                                ? 'trip_retention_value_count'
                                : 'trip_retention_value_size'),
                    child: TextField(
                      controller: _retentionValue,
                      enabled: !expungeLoading,
                      keyboardType:
                          _retentionPolicy == TripExpungePolicy.age ? TextInputType.text : TextInputType.number,
                      onChanged: (_) {
                        if (_retentionValidation != null) {
                          setState(() => _retentionValidation = null);
                        }
                      },
                      onSubmitted: (_) => _setRetention(),
                      decoration: InputDecoration(
                        labelText: FlutterI18n.translate(
                            context,
                            _retentionPolicy == TripExpungePolicy.age
                                ? 'trip_retention_value_age'
                                : _retentionPolicy == TripExpungePolicy.count
                                    ? 'trip_retention_value_count'
                                    : 'trip_retention_value_size'),
                        errorText:
                            _retentionValidation == null ? null : FlutterI18n.translate(context, _retentionValidation!),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  label: FlutterI18n.translate(context, 'stats_rename_save'),
                  child: FilledButton(
                    onPressed: expungeLoading ? null : _setRetention,
                    child: Text(FlutterI18n.translate(context, 'stats_rename_save')),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: FlutterI18n.translate(context, 'trip_reset_now'),
                child: FilledButton.icon(
                  onPressed: loading ? null : _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(FlutterI18n.translate(context, 'trip_reset_now')),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child:
                      Text(_errorText(context, _error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _duration(int seconds) => '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _retentionValue.dispose();
    super.dispose();
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            trailing: Text(value, style: Theme.of(context).textTheme.titleLarge)),
      );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: text,
        child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(child: Column(children: [Icon(icon, size: 40), const SizedBox(height: 12), Text(text)]))),
      );
}
