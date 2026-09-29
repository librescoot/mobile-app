import 'package:scooter_core/navigation.dart';
import 'package:scooter_flutter/navigation_runtime.dart';

/// In-memory navigation for demo mode; no destination reaches a scooter.
class DemoNavigationRuntime extends NavigationRuntime {
  DemoNavigationRuntime({required void Function(bool active) onActiveChanged, required super.changed})
      : _onActiveChanged = onActiveChanged,
        super(
          loadPending: () async => null,
          savePending: (_) async {},
          failed: (_, __) {},
        );

  final void Function(bool active) _onActiveChanged;
  final _favorites = <String, NavigationDestination>{};
  NavigationDestination? _demoPending;
  NavigationDestination? _demoActive;
  NavigationRoutePlan _demoPlan = const NavigationRoutePlan(stops: [], currentStep: 0);
  int _nextFavorite = 1;

  @override
  NavigationDestination? get pending => _demoPending?.copy();
  @override
  NavigationDestination? get active => _demoActive?.copy();
  @override
  NavigationRoutePlan get plan => _demoPlan.copy();

  @override
  Future<void> setPending(NavigationDestination? destination) async {
    _demoPending = destination?.copy();
    changed();
  }

  @override
  void setActive(NavigationDestination? destination) {
    _demoActive = destination?.copy();
    _onActiveChanged(destination != null);
    changed();
  }

  @override
  void navigationChanged(bool? active) {
    if (active != true) setActive(null);
  }

  @override
  Future<void> navigate(NavigationDestination destination, {bool favorite = false}) async {
    setActive(destination);
    _demoPending = null;
  }

  @override
  Future<void> cancel() async => setActive(null);

  @override
  Future<List<NavigationDestination>> listFavorites() async =>
      _favorites.values.map((destination) => destination.copy()).toList();

  @override
  Future<String> saveFavorite(NavigationDestination destination) async {
    final id = 'demo-${_nextFavorite++}';
    _favorites[id] = destination.copy()..id = id;
    changed();
    return id;
  }

  @override
  Future<void> deleteFavorite(String id) async {
    _favorites.remove(id);
    changed();
  }

  @override
  Future<String> renameFavorite(NavigationDestination destination, String name) async {
    final id = destination.id!;
    _favorites[id] = destination.copy()..name = name;
    changed();
    return id;
  }

  @override
  Future<NavigationRoutePlan> refreshPlan() async => _demoPlan.copy();

  @override
  Future<void> addStop(NavigationDestination stop) async {
    _demoPlan = NavigationRoutePlan(stops: [..._demoPlan.stops, stop.copy()], currentStep: _demoPlan.currentStep);
    changed();
  }

  @override
  Future<void> removeStopAt(int index) async {
    final stops = [..._demoPlan.stops];
    if (index < 1 || index > stops.length) throw RangeError.index(index, stops);
    stops.removeAt(index - 1);
    _demoPlan = NavigationRoutePlan(stops: stops, currentStep: _demoPlan.currentStep.clamp(0, stops.length));
    changed();
  }

  @override
  Future<void> skipStop() async {
    _demoPlan = NavigationRoutePlan(
      stops: _demoPlan.stops,
      currentStep: (_demoPlan.currentStep + 1).clamp(0, _demoPlan.stops.length),
    );
    changed();
  }

  @override
  Future<void> clearPlan() async {
    _demoPlan = const NavigationRoutePlan(stops: [], currentStep: 0);
    changed();
  }

  @override
  Future<void> reorderPlan(List<NavigationDestination> ordered) async {
    _demoPlan = NavigationRoutePlan(stops: ordered.map((stop) => stop.copy()).toList(), currentStep: 0);
    changed();
  }
}
