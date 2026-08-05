import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restaurant_app/Presentation/core/di/injection_container.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_cloud_service.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_manager.dart';
import 'package:restaurant_app/Presentation/core/sync/sync_record.dart';

class SyncState {
  final List<SyncRecord> registros;
  final bool isLoading;
  final bool isSyncing;
  final bool isCheckingCloud;
  final bool? cloudAvailable;
  final String? cloudStatusMessage;
  final DateTime? ultimaSync;
  final String? error;
  final String? successMessage;

  const SyncState({
    this.registros = const [],
    this.isLoading = false,
    this.isSyncing = false,
    this.isCheckingCloud = false,
    this.cloudAvailable,
    this.cloudStatusMessage,
    this.ultimaSync,
    this.error,
    this.successMessage,
  });

  List<SyncRecord> get pendientes =>
      registros.where((record) => !record.sincronizado).toList();
  List<SyncRecord> get sincronizados =>
      registros.where((record) => record.sincronizado).toList();
  int get totalPendientes => pendientes.length;
  bool get tienePendientes => pendientes.isNotEmpty;

  SyncState copyWith({
    List<SyncRecord>? registros,
    bool? isLoading,
    bool? isSyncing,
    bool? isCheckingCloud,
    bool? cloudAvailable,
    String? cloudStatusMessage,
    bool clearCloudStatus = false,
    DateTime? ultimaSync,
    String? error,
    bool clearError = false,
    String? successMessage,
    bool clearSuccess = false,
  }) => SyncState(
    registros: registros ?? this.registros,
    isLoading: isLoading ?? this.isLoading,
    isSyncing: isSyncing ?? this.isSyncing,
    isCheckingCloud: isCheckingCloud ?? this.isCheckingCloud,
    cloudAvailable: cloudAvailable ?? this.cloudAvailable,
    cloudStatusMessage: clearCloudStatus
        ? null
        : cloudStatusMessage ?? this.cloudStatusMessage,
    ultimaSync: ultimaSync ?? this.ultimaSync,
    error: clearError ? null : error ?? this.error,
    successMessage: clearSuccess ? null : successMessage ?? this.successMessage,
  );
}

class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier({
    required SyncManager syncManager,
    required SyncCloudService cloudService,
  }) : _syncManager = syncManager,
       _cloudService = cloudService,
       super(const SyncState()) {
    loadRegistros();
    checkCloudAvailability();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => loadRegistros(),
    );
  }

  final SyncManager _syncManager;
  final SyncCloudService _cloudService;
  Timer? _timer;

  bool _isCloudRecord(SyncRecord record) => !record.tabla.startsWith('_local_');

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> loadRegistros() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final pending = await _syncManager.obtenerPendientes();
      final synced = await _syncManager.obtenerSincronizados();
      state = state.copyWith(
        isLoading: false,
        registros: [...pending, ...synced],
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> checkCloudAvailability() async {
    state = state.copyWith(
      isCheckingCloud: true,
      clearCloudStatus: true,
      clearError: true,
    );
    if (!_cloudService.isCloudSyncSupportedPlatform) {
      state = state.copyWith(
        isCheckingCloud: false,
        cloudAvailable: false,
        cloudStatusMessage: _cloudService.unsupportedPlatformMessage,
      );
      return;
    }
    try {
      await _cloudService.ensureAvailable();
      state = state.copyWith(
        isCheckingCloud: false,
        cloudAvailable: true,
        cloudStatusMessage: 'Nube disponible para sincronizar',
      );
    } catch (_) {
      state = state.copyWith(
        isCheckingCloud: false,
        cloudAvailable: false,
        cloudStatusMessage: 'Nube no disponible. Revisa Realtime Database.',
      );
    }
  }

  Future<void> sincronizarAhora() async {
    if (!state.tienePendientes) {
      state = state.copyWith(
        successMessage: 'No hay operaciones pendientes de sincronizar',
      );
      return;
    }
    state = state.copyWith(isSyncing: true, clearError: true);
    if (!_cloudService.isCloudSyncSupportedPlatform) {
      state = state.copyWith(
        isSyncing: false,
        ultimaSync: DateTime.now(),
        cloudAvailable: false,
        cloudStatusMessage: _cloudService.unsupportedPlatformMessage,
        successMessage:
            'Modo local activo: sincronizacion cloud deshabilitada.',
      );
      await loadRegistros();
      return;
    }

    final pending = (await _syncManager.obtenerPendientesParaEnvio(
      limit: 1000,
      forzar: true,
    )).where(_isCloudRecord).toList();
    if (pending.isEmpty) {
      state = state.copyWith(
        isSyncing: false,
        ultimaSync: DateTime.now(),
        successMessage: 'No hay operaciones cloud pendientes.',
      );
      await loadRegistros();
      return;
    }

    try {
      await _cloudService.ensureAvailable();
      state = state.copyWith(
        cloudAvailable: true,
        cloudStatusMessage: 'Nube disponible para sincronizar',
      );
    } catch (error) {
      state = state.copyWith(
        isSyncing: false,
        cloudAvailable: false,
        cloudStatusMessage: 'Nube no disponible. Revisa Realtime Database.',
        error: error.toString(),
      );
      await loadRegistros();
      return;
    }

    var processed = 0;
    var errors = 0;
    String? firstError;
    for (final record in pending) {
      try {
        await _cloudService.pushRecord(record);
        await _syncManager.marcarSincronizado(record.id);
        await _syncManager.registrarAuditoria(
          direction: 'push',
          status: 'success',
          tabla: record.tabla,
          registroId: record.registroId,
          restaurantId: record.restaurantId,
          syncRecordId: record.id,
        );
        processed++;
      } catch (error) {
        await _syncManager.incrementarIntentos(record.id);
        await _syncManager.registrarAuditoria(
          direction: 'push',
          status: 'error',
          tabla: record.tabla,
          registroId: record.registroId,
          restaurantId: record.restaurantId,
          syncRecordId: record.id,
          detail: error.toString(),
        );
        errors++;
        firstError ??= '${record.tabla}/${record.registroId}: $error';
        debugPrint('SYNC_TAB_PUSH_ERROR $firstError');
      }
    }
    await loadRegistros();
    state = state.copyWith(
      isSyncing: false,
      ultimaSync: DateTime.now(),
      error: firstError,
      clearError: firstError == null,
      successMessage: errors == 0
          ? '$processed operaciones cloud sincronizadas.'
          : null,
      clearSuccess: errors > 0,
    );
  }

  Future<void> limpiarHistorial({int dias = 7}) async {
    state = state.copyWith(isLoading: true);
    try {
      await _syncManager.limpiarSincronizados(dias: dias);
      await loadRegistros();
      state = state.copyWith(
        isLoading: false,
        successMessage: 'Historial limpiado (registros > $dias dias)',
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  void clearMessages() =>
      state = state.copyWith(clearError: true, clearSuccess: true);
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(syncManager: sl(), cloudService: sl());
});
