import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:scooter_flutter/trip_history_commands.dart';
import 'package:unustasis/scooter_service.dart';

String _text(BuildContext context, String de, String en, String nl, String fr) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'de':
      return de;
    case 'nl':
      return nl;
    case 'fr':
      return fr;
    default:
      return en;
  }
}

String _date(BuildContext context, int seconds) {
  if (seconds < 1577836800 || seconds > 253402300799) {
    return _text(context, 'Datum unbekannt', 'Unknown date', 'Datum onbekend', 'Date inconnue');
  }
  final value = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal();
  final local = MaterialLocalizations.of(context);
  return '${local.formatMediumDate(value)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(value), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});
  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  ScooterService? _service;
  String? _scooterId, _cursor;
  bool _connected = false, _loading = false;
  int _generation = 0;
  Object? _error;
  final List<TripHistoryEntry> _trips = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<ScooterService>();
    if (identical(service, _service)) return;
    _service?.removeListener(_connectionChanged);
    _service = service;
    service.addListener(_connectionChanged);
    _connectionChanged();
  }

  void _connectionChanged() {
    final service = _service!;
    if (_connected == service.connected && _scooterId == service.currentScooterId) return;
    _connected = service.connected;
    _scooterId = service.currentScooterId;
    _generation++;
    _trips.clear();
    _cursor = null;
    _error = null;
    _loading = false;
    if (mounted) setState(() {});
    if (_connected) _load();
  }

  Future<void> _load({bool more = false}) async {
    final service = _service;
    if (service == null || !service.connected || _loading || (more && _cursor == null)) return;
    final generation = ++_generation;
    final cursor = more ? _cursor : null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page =
          await service.actions.readTripHistory(cursor: cursor, isActive: () => mounted && generation == _generation);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _trips.clear();
        _trips.addAll(page.trips);
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _service?.removeListener(_connectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _text(context, 'Fahrtenverlauf', 'Trip history', 'Ritgeschiedenis', 'Historique des trajets');
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loading || !_connected ? null : () => _load())
      ]),
      body: !_connected
          ? Center(
              child: Text(_text(context, 'Mit dem Roller verbinden', 'Connect to the scooter', 'Verbind met de scooter',
                  'Connectez le scooter')))
          : _loading && _trips.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _trips.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error is UnsupportedError
                          ? _text(context, 'Fahrtenverlauf wird nicht unterstützt', 'Trip history is not supported',
                              'Ritgeschiedenis wordt niet ondersteund', 'Historique non pris en charge')
                          : _text(context, 'Fahrten konnten nicht geladen werden', 'Could not load trips',
                              'Ritten laden mislukt', 'Chargement des trajets impossible')),
                      TextButton(
                          onPressed: () => _load(),
                          child: Text(_text(context, 'Erneut versuchen', 'Retry', 'Opnieuw', 'Réessayer'))),
                    ]))
                  : _trips.isEmpty
                      ? Center(
                          child: Text(_text(context, 'Noch keine abgeschlossenen Fahrten', 'No completed trips yet',
                              'Nog geen voltooide ritten', 'Aucun trajet terminé')))
                      : RefreshIndicator(
                          onRefresh: () => _load(),
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _trips.length + (_cursor != null ? 1 : 0) + (_error != null ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _trips.length && _cursor != null) {
                                return ListTile(
                                    title: Text(_text(
                                        context, 'Weitere Fahrten', 'More trips', 'Meer ritten', 'Plus de trajets')),
                                    trailing:
                                        _loading ? const CircularProgressIndicator() : const Icon(Icons.expand_more),
                                    onTap: _loading ? null : () => _load(more: true));
                              }
                              if (index >= _trips.length) {
                                return ListTile(
                                    title: Text(_text(context, 'Laden fehlgeschlagen', 'Loading failed',
                                        'Laden mislukt', 'Échec du chargement')),
                                    onTap: () => _load(more: _cursor != null));
                              }
                              final trip = _trips[index];
                              return ListTile(
                                leading: const Icon(Icons.route_outlined),
                                title: Text(_date(context, trip.startedAtSeconds)),
                                subtitle: Text('${trip.readyDurationSeconds ~/ 60} min'),
                                trailing: Text('${(trip.distanceMeters / 1000).toStringAsFixed(1)} km'),
                                onTap: () => Navigator.push(
                                    context, MaterialPageRoute(builder: (_) => _TripDetailScreen(trip: trip))),
                              );
                            },
                          ),
                        ),
    );
  }
}

class _TripDetailScreen extends StatefulWidget {
  const _TripDetailScreen({required this.trip});
  final TripHistoryEntry trip;
  @override
  State<_TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<_TripDetailScreen> {
  int _generation = 0;
  bool _loading = false, _showTrace = false, _onlineMap = false;
  Object? _error;
  List<TripHistoryPoint> _points = [];
  ScooterService? _service;
  String? _ownerScooterId;
  TripHistoryEntry? _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<ScooterService>();
    if (identical(service, _service)) return;
    _service?.removeListener(_connectionChanged);
    _service = service;
    _ownerScooterId = service.currentScooterId;
    service.addListener(_connectionChanged);
    _loadDetail();
  }

  void _connectionChanged() {
    final service = _service!;
    if (service.connected && service.currentScooterId == _ownerScooterId) return;
    _generation++;
    if (mounted) {
      setState(() {
        _loading = false;
        _points = [];
        _showTrace = false;
        _detail = null;
        _error = StateError('disconnected');
      });
    }
  }

  Future<void> _loadDetail() async {
    final service = _service;
    if (service == null || !service.connected || service.currentScooterId != _ownerScooterId || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await service.actions.readTripHistoryEntry(widget.trip.id,
          isActive: () => mounted && generation == _generation && service.currentScooterId == _ownerScooterId);
      if (mounted && generation == _generation) setState(() => _detail = detail);
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _service?.removeListener(_connectionChanged);
    super.dispose();
  }

  Future<void> _loadPoints() async {
    if (_loading) return;
    final service = context.read<ScooterService>();
    if (!service.connected || service.currentScooterId != _ownerScooterId) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = <TripHistoryPoint>[];
      var after = 0;
      while (true) {
        final page = await service.actions.readTripHistoryPoints(widget.trip.id,
            afterId: after,
            isActive: () => mounted && generation == _generation && service.currentScooterId == _ownerScooterId);
        if (!mounted || generation != _generation) return;
        result.addAll(page.points);
        final next = page.nextAfterId;
        if (next == null) break;
        if (next <= after || result.length >= 10000) throw StateError('GPS trace too long');
        after = next;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _points = result;
        _showTrace = true;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  List<Polyline> _segments(Color color) {
    final lines = <Polyline>[];
    var points = <LatLng>[];
    int? previous;
    for (final point in _points) {
      if (previous != null &&
          point.timestampMs > 0 &&
          (point.timestampMs < previous || point.timestampMs - previous > 180000)) {
        if (points.length > 1) lines.add(Polyline(points: points, strokeWidth: 4, color: color));
        points = [];
      }
      points.add(LatLng(point.latitude, point.longitude));
      previous = point.timestampMs;
    }
    if (points.length > 1) lines.add(Polyline(points: points, strokeWidth: 4, color: color));
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final trip = _detail ?? widget.trip;
    final locations = _points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_text(context, 'Fahrt', 'Trip', 'Rit', 'Trajet'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_loading && _detail == null) const Center(child: CircularProgressIndicator()),
        if (_detail == null && !_loading)
          ListTile(
              title: Text(_error is TripHistoryException && (_error as TripHistoryException).code == 'not-found'
                  ? _text(context, 'Diese Fahrt ist nicht mehr gespeichert', 'This trip is no longer stored',
                      'Deze rit is niet meer opgeslagen', "Ce trajet n'est plus enregistré")
                  : _text(context, 'Fahrt nicht verfügbar', 'Trip unavailable', 'Rit niet beschikbaar',
                      'Trajet indisponible')),
              onTap: _loadDetail),
        if (_detail != null)
          ListTile(
              title: Text(_date(context, trip.startedAtSeconds)),
              subtitle: Text(
                  '${(trip.distanceMeters / 1000).toStringAsFixed(1)} km · ${trip.readyDurationSeconds ~/ 60} min')),
        if (_detail != null && trip.averageSpeedKmh != null)
          ListTile(
              title: Text(_text(context, 'Durchschnitt', 'Average', 'Gemiddeld', 'Moyenne')),
              trailing: Text('${trip.averageSpeedKmh!.toStringAsFixed(1)} km/h')),
        if (_detail != null && trip.maxRecordedGpsSpeedKmh != null)
          ListTile(
              title: const Text('GPS max'), trailing: Text('${trip.maxRecordedGpsSpeedKmh!.toStringAsFixed(1)} km/h')),
        if (_detail != null && trip.pointCount > 0 && !_showTrace)
          ListTile(
              leading: const Icon(Icons.map_outlined),
              title:
                  Text(_text(context, 'GPS-Spur ansehen', 'View GPS trace', 'GPS-spoor bekijken', 'Voir la trace GPS')),
              trailing: _loading ? const CircularProgressIndicator() : const Icon(Icons.chevron_right),
              onTap: _loading ? null : _loadPoints),
        if (_detail != null && trip.pointCount == 0)
          ListTile(title: Text(_text(context, 'Keine GPS-Spur', 'No GPS trace', 'Geen GPS-spoor', 'Aucune trace GPS'))),
        if (_detail != null && _error != null)
          ListTile(
              title: Text(_text(context, 'GPS-Spur konnte nicht geladen werden', 'Could not load GPS trace',
                  'GPS-spoor laden mislukt', 'Chargement GPS impossible')),
              onTap: _loadPoints),
        if (_showTrace && locations.length < 2)
          ListTile(title: Text(_text(context, 'Keine GPS-Spur', 'No GPS trace', 'Geen GPS-spoor', 'Aucune trace GPS'))),
        if (_showTrace && locations.length >= 2) ...[
          SizedBox(
              height: 320,
              child: Stack(children: [
                FlutterMap(
                    options: MapOptions(
                        initialCameraFit: CameraFit.coordinates(
                            coordinates: locations, padding: const EdgeInsets.all(35), maxZoom: 16)),
                    children: [
                      if (_onlineMap)
                        TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'org.librescoot.mobile.unu'),
                      PolylineLayer(polylines: _segments(Theme.of(context).colorScheme.primary)),
                    ]),
                if (_onlineMap)
                  const Positioned(
                      right: 4,
                      bottom: 4,
                      child: ColoredBox(
                          color: Colors.white70,
                          child: Text('© OpenStreetMap contributors',
                              style: TextStyle(color: Colors.black, fontSize: 10)))),
              ])),
          if (!_onlineMap) ...[
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_text(context, 'GPS-Spur ohne Hintergrundkarte', 'GPS trace without a basemap',
                    'GPS-spoor zonder achtergrondkaart', 'Trace GPS sans fond de carte'))),
            TextButton(
                onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                              title: Text(_text(context, 'Online-Karte laden?', 'Load online map?',
                                  'Online kaart laden?', 'Charger la carte en ligne ?')),
                              content: Text(_text(
                                  context,
                                  'Der angezeigte Kartenausschnitt und deine IP-Adresse werden an OpenStreetMap übertragen.',
                                  'The displayed map area and your IP address will be sent to OpenStreetMap.',
                                  'Het kaartgebied en je IP-adres worden naar OpenStreetMap verzonden.',
                                  'La zone affichée et votre adresse IP seront envoyées à OpenStreetMap.')),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
                                TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text(
                                        _text(context, 'Karte laden', 'Load map', 'Kaart laden', 'Charger la carte')))
                              ],
                            )).then((ok) {
                      if (mounted && ok == true) setState(() => _onlineMap = true);
                    }),
                child: Text(_text(context, 'Online-Karte laden', 'Load online map', 'Online kaart laden',
                    'Charger la carte en ligne'))),
          ],
        ],
      ]),
    );
  }
}
