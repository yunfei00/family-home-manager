import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';
import 'models.dart';
import 'sync_state.dart';

class SyncConflictException implements Exception {
  const SyncConflictException(this.currentRevision);

  final int currentRevision;

  @override
  String toString() =>
      '服务器已有较新版本（revision=$currentRevision），请先下载再决定是否覆盖。';
}

enum AutoSyncStatus {
  notConfigured,
  disabled,
  inSync,
  uploaded,
  downloaded,
  conflict,
  offline,
  inconsistent,
}

class AutoSyncResult {
  const AutoSyncResult({
    required this.status,
    required this.message,
    required this.profile,
    this.localDataChanged = false,
  });

  final AutoSyncStatus status;
  final String message;
  final SyncProfile profile;
  final bool localDataChanged;

  bool get isSuccess =>
      status == AutoSyncStatus.inSync ||
      status == AutoSyncStatus.uploaded ||
      status == AutoSyncStatus.downloaded;
}

class FamilySyncService {
  FamilySyncService._();

  static final FamilySyncService instance = FamilySyncService._();

  static const defaultServerUrl = 'http://106.52.122.214:8787';

  static const _serverUrlKey = 'sync_server_url';
  static const _familyIdKey = 'sync_family_id';
  static const _tokenKey = 'sync_token';
  static const _revisionKey = 'sync_revision';

  Future<SyncProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return SyncProfile(
      serverUrl: prefs.getString(_serverUrlKey) ?? defaultServerUrl,
      familyId: prefs.getString(_familyIdKey) ?? '',
      token: prefs.getString(_tokenKey) ?? '',
      revision: prefs.getInt(_revisionKey) ?? 0,
    );
  }

  Future<void> saveProfile(SyncProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, _normalizeUrl(profile.serverUrl));
    await prefs.setString(_familyIdKey, profile.familyId.trim());
    await prefs.setString(_tokenKey, profile.token.trim());
    await prefs.setInt(_revisionKey, profile.revision);
  }

  Future<bool> testConnection(String serverUrl) async {
    final response = await http
        .get(Uri.parse('${_normalizeUrl(serverUrl)}/health'))
        .timeout(const Duration(seconds: 8));
    return response.statusCode == 200;
  }

  Future<SyncProfile> createFamilySpace({
    required String serverUrl,
    required String familyName,
  }) async {
    final normalized = _normalizeUrl(serverUrl);
    final response = await http
        .post(
          Uri.parse('$normalized/api/v1/families'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': familyName.trim().isEmpty ? '我的家' : familyName.trim(),
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 201) {
      throw StateError(
        '创建家庭空间失败：HTTP ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final profile = SyncProfile(
      serverUrl: normalized,
      familyId: body['family_id'] as String,
      token: body['token'] as String,
      revision: (body['revision'] as num?)?.toInt() ?? 0,
    );
    await saveProfile(profile);
    await SyncStateStore.instance.markDirty();
    return profile;
  }

  Future<SyncProfile> pushBackup(SyncProfile profile) async {
    if (!profile.isConfigured) {
      throw StateError('请先配置家庭服务器');
    }

    final backup = await BackupService.instance.createBackupPayload();
    final response = await http
        .put(
          Uri.parse(
            '${_normalizeUrl(profile.serverUrl)}/api/v1/families/'
            '${Uri.encodeComponent(profile.familyId)}/backup',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${profile.token}',
          },
          body: jsonEncode({
            'expected_revision': profile.revision,
            'backup': backup,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 409) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw SyncConflictException(
        (body['current_revision'] as num?)?.toInt() ?? profile.revision,
      );
    }
    if (response.statusCode != 200) {
      throw StateError(
        '上传备份失败：HTTP ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final updated = SyncProfile(
      serverUrl: profile.serverUrl,
      familyId: profile.familyId,
      token: profile.token,
      revision: (body['revision'] as num).toInt(),
    );
    await saveProfile(updated);
    await SyncStateStore.instance.markClean();
    return updated;
  }

  Future<({SyncProfile profile, bool restored})> pullBackup(
    SyncProfile profile,
  ) async {
    if (!profile.isConfigured) {
      throw StateError('请先配置家庭服务器');
    }

    final response = await http
        .get(
          Uri.parse(
            '${_normalizeUrl(profile.serverUrl)}/api/v1/families/'
            '${Uri.encodeComponent(profile.familyId)}/backup',
          ),
          headers: {'Authorization': 'Bearer ${profile.token}'},
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw StateError(
        '下载备份失败：HTTP ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final revision = (body['revision'] as num?)?.toInt() ?? 0;
    final backup = body['backup'];

    var restored = false;
    if (backup is Map) {
      await BackupService.instance.restoreBackupPayload(
        Map<String, Object?>.from(backup.cast<String, Object?>()),
      );
      restored = true;
    }

    final updated = SyncProfile(
      serverUrl: profile.serverUrl,
      familyId: profile.familyId,
      token: profile.token,
      revision: revision,
    );
    await saveProfile(updated);
    await SyncStateStore.instance.markClean();
    return (profile: updated, restored: restored);
  }

  Future<({int revision, bool hasBackup})> fetchRemoteMeta(
    SyncProfile profile,
  ) async {
    if (!profile.isConfigured) {
      throw StateError('请先配置家庭服务器');
    }

    final response = await http
        .get(
          Uri.parse(
            '${_normalizeUrl(profile.serverUrl)}/api/v1/families/'
            '${Uri.encodeComponent(profile.familyId)}/meta',
          ),
          headers: {'Authorization': 'Bearer ${profile.token}'},
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw StateError(
        '读取服务器同步状态失败：HTTP ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      revision: (body['revision'] as num?)?.toInt() ?? 0,
      hasBackup: body['has_backup'] == true,
    );
  }

  Future<AutoSyncResult> autoSync({bool force = false}) async {
    var profile = await loadProfile();
    final localState = await SyncStateStore.instance.load();

    if (!profile.isConfigured) {
      return AutoSyncResult(
        status: AutoSyncStatus.notConfigured,
        message: '尚未配置家庭空间',
        profile: profile,
      );
    }

    if (!force && !localState.autoSyncEnabled) {
      return AutoSyncResult(
        status: AutoSyncStatus.disabled,
        message: '自动同步已关闭',
        profile: profile,
      );
    }

    try {
      final remote = await fetchRemoteMeta(profile);
      final decision = decideAutoSync(
        configured: profile.isConfigured,
        enabled: force || localState.autoSyncEnabled,
        dirty: localState.dirty,
        localRevision: profile.revision,
        remoteRevision: remote.revision,
      );

      switch (decision) {
        case AutoSyncDecision.upload:
          profile = await pushBackup(profile);
          return AutoSyncResult(
            status: AutoSyncStatus.uploaded,
            message: '本机更新已上传 · revision ${profile.revision}',
            profile: profile,
          );
        case AutoSyncDecision.download:
          if (!remote.hasBackup) {
            await SyncStateStore.instance.markClean();
            return AutoSyncResult(
              status: AutoSyncStatus.inSync,
              message: '服务器暂无备份，本机无需下载',
              profile: profile,
            );
          }
          final pulled = await pullBackup(profile);
          profile = pulled.profile;
          return AutoSyncResult(
            status: AutoSyncStatus.downloaded,
            message: '已下载服务器更新 · revision ${profile.revision}',
            profile: profile,
            localDataChanged: pulled.restored,
          );
        case AutoSyncDecision.conflict:
          return AutoSyncResult(
            status: AutoSyncStatus.conflict,
            message:
                '本机和服务器都有新修改，请进入“家庭与备份”手动处理',
            profile: profile,
          );
        case AutoSyncDecision.inconsistent:
          return AutoSyncResult(
            status: AutoSyncStatus.inconsistent,
            message:
                '同步版本不一致（本机 ${profile.revision} / 服务器 ${remote.revision}）',
            profile: profile,
          );
        case AutoSyncDecision.inSync:
          if (profile.revision != remote.revision) {
            profile = SyncProfile(
              serverUrl: profile.serverUrl,
              familyId: profile.familyId,
              token: profile.token,
              revision: remote.revision,
            );
            await saveProfile(profile);
          }
          await SyncStateStore.instance.markClean();
          return AutoSyncResult(
            status: AutoSyncStatus.inSync,
            message: '数据已同步 · revision ${profile.revision}',
            profile: profile,
          );
        case AutoSyncDecision.notConfigured:
          return AutoSyncResult(
            status: AutoSyncStatus.notConfigured,
            message: '尚未配置家庭空间',
            profile: profile,
          );
        case AutoSyncDecision.disabled:
          return AutoSyncResult(
            status: AutoSyncStatus.disabled,
            message: '自动同步已关闭',
            profile: profile,
          );
      }
    } on SyncConflictException catch (error) {
      return AutoSyncResult(
        status: AutoSyncStatus.conflict,
        message: '服务器已有新版本 revision ${error.currentRevision}',
        profile: profile,
      );
    } catch (_) {
      return AutoSyncResult(
        status: AutoSyncStatus.offline,
        message: '家庭服务器暂时不可连接，本机数据不受影响',
        profile: profile,
      );
    }
  }

  String _normalizeUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
