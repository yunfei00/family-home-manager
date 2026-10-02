import 'package:shared_preferences/shared_preferences.dart';

class SyncLocalState {
  const SyncLocalState({
    required this.dirty,
    required this.autoSyncEnabled,
    this.lastSuccessAt,
  });

  final bool dirty;
  final bool autoSyncEnabled;
  final DateTime? lastSuccessAt;
}

class SyncStateStore {
  SyncStateStore._();

  static final SyncStateStore instance = SyncStateStore._();

  static const _dirtyKey = 'sync_dirty';
  static const _autoSyncKey = 'sync_auto_enabled';
  static const _lastSuccessKey = 'sync_last_success_at';

  Future<SyncLocalState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawLast = prefs.getString(_lastSuccessKey);
    return SyncLocalState(
      dirty: prefs.getBool(_dirtyKey) ?? false,
      autoSyncEnabled: prefs.getBool(_autoSyncKey) ?? true,
      lastSuccessAt:
          rawLast == null ? null : DateTime.tryParse(rawLast),
    );
  }

  Future<void> markDirty() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dirtyKey, true);
  }

  Future<void> markClean() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dirtyKey, false);
    await prefs.setString(
      _lastSuccessKey,
      DateTime.now().toIso8601String(),
    );
  }

  Future<void> setAutoSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, enabled);
  }
}

enum AutoSyncDecision {
  notConfigured,
  disabled,
  inSync,
  upload,
  download,
  conflict,
  inconsistent,
}

AutoSyncDecision decideAutoSync({
  required bool configured,
  required bool enabled,
  required bool dirty,
  required int localRevision,
  required int remoteRevision,
}) {
  if (!configured) return AutoSyncDecision.notConfigured;
  if (!enabled) return AutoSyncDecision.disabled;

  if (remoteRevision == localRevision) {
    return dirty ? AutoSyncDecision.upload : AutoSyncDecision.inSync;
  }

  if (remoteRevision > localRevision) {
    return dirty ? AutoSyncDecision.conflict : AutoSyncDecision.download;
  }

  return AutoSyncDecision.inconsistent;
}
