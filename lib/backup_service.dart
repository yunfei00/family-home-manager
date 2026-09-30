import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/app_database.dart';

class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const backupFormat = 'family-home-manager-backup';
  static const backupFormatVersion = 1;
  static const databaseVersion = 7;

  Future<Map<String, Object?>> createBackupPayload() async {
    final tables = await AppDatabase.instance.exportBackupTables();
    final photoPaths = <String>{};

    for (final table in const ['locations', 'items']) {
      for (final row in tables[table] ?? const <Map<String, Object?>>[]) {
        final path = row['photo_path'] as String?;
        if (path != null && path.isNotEmpty) {
          photoPaths.add(path);
        }
      }
    }

    final photos = <String, String>{};
    for (final path in photoPaths) {
      final file = File(path);
      if (await file.exists()) {
        photos[path] = base64Encode(await file.readAsBytes());
      }
    }

    return <String, Object?>{
      'format': backupFormat,
      'format_version': backupFormatVersion,
      'database_version': databaseVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': tables,
      'photos': photos,
    };
  }

  Future<String?> exportBackupFile() async {
    final payload = await createBackupPayload();
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(payload));
    final now = DateTime.now();
    final filename =
        'family-home-manager-${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}.json';

    return FilePicker.platform.saveFile(
      dialogTitle: '保存家庭管理备份',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
  }

  Future<bool> importBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择家庭管理备份',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return false;

    final picked = result.files.single;
    List<int>? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null) {
      throw const FormatException('无法读取备份文件');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('备份文件格式不正确');
    }

    await restoreBackupPayload(
      Map<String, Object?>.from(decoded.cast<String, Object?>()),
    );
    return true;
  }

  Future<void> restoreBackupPayload(Map<String, Object?> payload) async {
    if (payload['format'] != backupFormat) {
      throw const FormatException('不是 Family Home Manager 备份文件');
    }
    final formatVersion = payload['format_version'];
    if (formatVersion is! num || formatVersion.toInt() != backupFormatVersion) {
      throw const FormatException('暂不支持这个备份版本');
    }

    final rawTables = payload['tables'];
    if (rawTables is! Map) {
      throw const FormatException('备份缺少数据库内容');
    }

    final tables = <String, Object?>{
      for (final entry in rawTables.entries)
        entry.key.toString(): entry.value,
    };

    final restoredPhotoPaths = await _restorePhotos(payload['photos']);
    for (final tableName in const ['locations', 'items']) {
      final rows = tables[tableName];
      if (rows is! List) continue;
      for (final rawRow in rows) {
        if (rawRow is! Map) continue;
        final row = rawRow.cast<String, Object?>();
        final originalPath = row['photo_path'] as String?;
        if (originalPath == null || originalPath.isEmpty) continue;
        row['photo_path'] = restoredPhotoPaths[originalPath] ??
            (await File(originalPath).exists() ? originalPath : null);
      }
    }

    await AppDatabase.instance.replaceAllFromBackup(tables);
  }

  Future<Map<String, String>> _restorePhotos(Object? rawPhotos) async {
    if (rawPhotos is! Map || rawPhotos.isEmpty) {
      return const <String, String>{};
    }

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'photos'));
    await directory.create(recursive: true);

    final result = <String, String>{};
    var index = 0;
    for (final entry in rawPhotos.entries) {
      final originalPath = entry.key.toString();
      final encoded = entry.value;
      if (encoded is! String || encoded.isEmpty) continue;

      final extension = p.extension(originalPath).isEmpty
          ? '.jpg'
          : p.extension(originalPath);
      final target = File(
        p.join(
          directory.path,
          'restore_${DateTime.now().microsecondsSinceEpoch}_${index++}$extension',
        ),
      );
      await target.writeAsBytes(base64Decode(encoded), flush: true);
      result[originalPath] = target.path;
    }
    return result;
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
