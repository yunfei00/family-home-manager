import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';
import 'models.dart';

class SyncConflictException implements Exception {
  const SyncConflictException(this.currentRevision);

  final int currentRevision;

  @override
  String toString() =>
      '服务器已有较新版本（revision=$currentRevision），请先下载再决定是否覆盖。';
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
    return (profile: updated, restored: restored);
  }

  String _normalizeUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
