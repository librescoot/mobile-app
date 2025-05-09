import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:logging/logging.dart';

import '../../../domain/repositories/scooter_repository.dart';
import 'scooter_event.dart';
import 'scooter_state.dart';

/// BLoC for managing scooter state
class ScooterBloc extends Bloc<ScooterEvent, ScooterState> {
  final ScooterRepository _repository;
  final Logger _logger = Logger('ScooterBloc');
  
  StreamSubscription? _scooterUpdateSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _discoverySubscription;
  
  ScooterBloc(this._repository) : super(ScootersInitial()) {
    on<LoadScooters>(_onLoadScooters);
    on<ConnectToScooter>(_onConnectToScooter);
    on<DisconnectScooter>(_onDisconnectScooter);
    on<ExecuteScooterCommand>(_onExecuteCommand);
    on<ScanForScooters>(_onScanForScooters);
    on<StopScanningForScooters>(_onStopScanningForScooters);
    on<RenameScooter>(_onRenameScooter);
    on<SetScooterAutoConnect>(_onSetScooterAutoConnect);
    on<DeleteScooter>(_onDeleteScooter);
    on<ScooterUpdated>(_onScooterUpdated);
    
    // Subscribe to repository updates
    _scooterUpdateSubscription = _repository.getScooterUpdates().listen(
      (scooter) => add(ScooterUpdated(scooter)),
      onError: (error) => _logger.severe('Error from scooter updates', error),
    );
    
    // Subscribe to repository errors
    _errorSubscription = _repository.getErrorStream().listen(
      (error) => _logger.severe('Repository error', error),
    );
  }
  
  Future<void> _onLoadScooters(LoadScooters event, Emitter<ScooterState> emit) async {
    try {
      final scooters = await _repository.getAllScooters();
      emit(ScootersLoaded(scooters));
    } catch (e) {
      _logger.severe('Failed to load scooters', e);
      emit(ScooterError('Failed to load scooters: ${e.toString()}', state.scooters));
    }
  }
  
  Future<void> _onConnectToScooter(
    ConnectToScooter event, 
    Emitter<ScooterState> emit
  ) async {
    emit(ScooterConnecting(event.scooterId, state.scooters));
    try {
      await _repository.connect(event.scooterId);
      final scooters = await _repository.getAllScooters();
      emit(ScootersLoaded(scooters));
    } catch (e) {
      _logger.severe('Connection failed', e);
      emit(ScooterError('Connection failed: ${e.toString()}', state.scooters));
    }
  }
  
  Future<void> _onDisconnectScooter(
    DisconnectScooter event, 
    Emitter<ScooterState> emit
  ) async {
    try {
      await _repository.disconnect(event.scooterId);
      final scooters = await _repository.getAllScooters();
      emit(ScootersLoaded(scooters));
    } catch (e) {
      _logger.severe('Disconnection failed', e);
      emit(ScooterError('Disconnection failed: ${e.toString()}', state.scooters));
    }
  }
  
  Future<void> _onExecuteCommand(
    ExecuteScooterCommand event, 
    Emitter<ScooterState> emit
  ) async {
    emit(ScooterCommandExecuting(event.command, state.scooters));
    try {
      await _repository.executeCommand(event.command);
      final scooters = await _repository.getAllScooters();
      emit(ScootersLoaded(scooters));
    } catch (e) {
      _logger.severe('Command execution failed', e);
      emit(ScooterError('Command failed: ${e.toString()}', state.scooters));
    }
  }
  
  Future<void> _onScanForScooters(
    ScanForScooters event, 
    Emitter<ScooterState> emit
  ) async {
    try {
      final discoveries = <ScooterDiscovery>[];
      emit(ScootersScanning(state.scooters, discoveries));
      
      // Subscribe to discovery stream
      _discoverySubscription?.cancel();
      _discoverySubscription = _repository.getScooterDiscoveryStream().listen(
        (discovery) {
          discoveries.add(discovery);
          emit(ScootersScanning(state.scooters, List.from(discoveries)));
        },
        onError: (error) {
          _logger.severe('Error during scan', error);
          emit(ScooterError('Scan error: ${error.toString()}', state.scooters));
        },
      );
      
      // Start scan
      await _repository.scanForScooters();
    } catch (e) {
      _logger.severe('Failed to start scan', e);
      emit(ScooterError('Failed to start scan: ${e.toString()}', state.scooters));
    }
  }
  
  Future<void> _onStopScanningForScooters(
    StopScanningForScooters event, 
    Emitter<ScooterState> emit
  ) async {
    try {
      await _repository.stopScan();
      _discoverySubscription?.cancel();
      _discoverySubscription = null;
      
      final scooters = await _repository.getAllScooters();
      emit(ScootersLoaded(scooters));
    } catch (e) {
      _logger.severe('Failed to stop scan', e);
      emit(ScooterError('Failed to stop scan: ${e.toString()}', state.scooters));
    }
  }
  
  Future<void> _onRenameScooter(
    RenameScooter event, 
    Emitter<ScooterState> emit
  ) async {
    try {
      final scooter = await _repository.getScooter(event.scooterId);
      if (scooter != null) {
        final updatedScooter = scooter.copyWith(name: event.newName);
        await _repository.saveScooter(updatedScooter);
        
        final scooters = await _repository.getAllScooters();
        emit(ScootersLoaded(scooters));
      }
    } catch (e) {
      _logger.severe('Failed to rename scooter', e);
      emit(ScooterError('Failed to rename scooter: ${e.toString()}', state.scooters));
    }
  }
  
  Future<void> _onSetScooterAutoConnect(
    SetScooterAutoConnect event, 
    Emitter<ScooterState> emit
  ) async {
    try {
      final scooter = await _repository.getScooter(event.scooterId);
      if (scooter != null) {
        final updatedScooter = scooter.copyWith(autoConnect: event.autoConnect);
        await _repository.saveScooter(updatedScooter);
        
        final scooters = await _repository.getAllScooters();
        emit(ScootersLoaded(scooters));
      }
    } catch (e) {
      _logger.severe('Failed to update auto-connect setting', e);
      emit(ScooterError('Failed to update auto-connect: ${e.toString()}', state.scooters));
    }
  }
  
  Future<void> _onDeleteScooter(
    DeleteScooter event, 
    Emitter<ScooterState> emit
  ) async {
    try {
      await _repository.deleteScooter(event.scooterId);
      
      final scooters = await _repository.getAllScooters();
      emit(ScootersLoaded(scooters));
    } catch (e) {
      _logger.severe('Failed to delete scooter', e);
      emit(ScooterError('Failed to delete scooter: ${e.toString()}', state.scooters));
    }
  }
  
  void _onScooterUpdated(
    ScooterUpdated event, 
    Emitter<ScooterState> emit
  ) {
    final updatedScooters = [
      ...state.scooters.where((s) => s.id != event.scooter.id),
      event.scooter,
    ];
    
    emit(ScootersLoaded(updatedScooters));
  }
  
  @override
  Future<void> close() {
    _scooterUpdateSubscription?.cancel();
    _errorSubscription?.cancel();
    _discoverySubscription?.cancel();
    return super.close();
  }
}