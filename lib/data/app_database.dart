import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dbPath, 'family_home_manager.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            parent_id INTEGER,
            type TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT 'single',
            location_id INTEGER NOT NULL,
            quantity REAL NOT NULL DEFAULT 1,
            unit TEXT NOT NULL DEFAULT '个',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(location_id) REFERENCES locations(id)
          )
        ''');

        await database.execute('''
          CREATE TABLE inventory_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            location_id INTEGER NOT NULL,
            started_at TEXT NOT NULL,
            completed_at TEXT NOT NULL,
            total_count INTEGER NOT NULL,
            present_count INTEGER NOT NULL,
            missing_count INTEGER NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE inventory_checks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            present INTEGER NOT NULL,
            FOREIGN KEY(session_id) REFERENCES inventory_sessions(id),
            FOREIGN KEY(item_id) REFERENCES items(id)
          )
        ''');

        final now = DateTime.now().toIso8601String();
        await database.insert('locations', {
          'name': '我的家',
          'parent_id': null,
          'type': 'home',
          'path': '我的家',
          'created_at': now,
        });
      },
    );

    _database = db;
    return db;
  }

  Future<List<LocationNode>> getLocations() async {
    final db = await database;
    final rows = await db.query('locations', orderBy: 'path ASC');
    return rows.map(LocationNode.fromMap).toList();
  }

  Future<int> addLocation({
    required String name,
    required int parentId,
    required String type,
  }) async {
    final db = await database;
    final parentRows = await db.query(
      'locations',
      where: 'id = ?',
      whereArgs: [parentId],
      limit: 1,
    );
    if (parentRows.isEmpty) {
      throw StateError('Parent location not found');
    }

    final parentPath = parentRows.first['path'] as String;
    final cleanName = name.trim();
    final now = DateTime.now().toIso8601String();

    return db.insert('locations', {
      'name': cleanName,
      'parent_id': parentId,
      'type': type,
      'path': '$parentPath / $cleanName',
      'created_at': now,
    });
  }

  Future<List<HomeItem>> getItems({String query = ''}) async {
    final db = await database;
    final clean = query.trim();
    final where = clean.isEmpty
        ? null
        : '(i.name LIKE ? OR i.category LIKE ? OR i.notes LIKE ?)';
    final args = clean.isEmpty
        ? null
        : List<Object?>.filled(3, '%$clean%');

    final rows = await db.rawQuery(
      '''
      SELECT i.*, l.path AS location_path
      FROM items i
      JOIN locations l ON l.id = i.location_id
      ${where == null ? '' : 'WHERE $where'}
      ORDER BY i.updated_at DESC
      ''',
      args,
    );
    return rows.map(HomeItem.fromMap).toList();
  }

  Future<List<HomeItem>> getItemsAtLocation(int locationId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT i.*, l.path AS location_path
      FROM items i
      JOIN locations l ON l.id = i.location_id
      WHERE i.location_id = ?
      ORDER BY i.name COLLATE NOCASE ASC
      ''',
      [locationId],
    );
    return rows.map(HomeItem.fromMap).toList();
  }

  Future<int> addItem({
    required String name,
    required String category,
    required String kind,
    required int locationId,
    required double quantity,
    required String unit,
    required String notes,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.insert('items', {
      'name': name.trim(),
      'category': category.trim(),
      'kind': kind,
      'location_id': locationId,
      'quantity': quantity,
      'unit': unit.trim().isEmpty ? '个' : unit.trim(),
      'notes': notes.trim(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<Map<int, int>> getItemCountsByLocation() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT location_id, COUNT(*) AS item_count FROM items GROUP BY location_id',
    );
    return {
      for (final row in rows)
        row['location_id'] as int: (row['item_count'] as num).toInt(),
    };
  }

  Future<int> createInventorySession({
    required int locationId,
    required Map<int, bool> checks,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final present = checks.values.where((value) => value).length;
      final missing = checks.length - present;

      final sessionId = await txn.insert('inventory_sessions', {
        'location_id': locationId,
        'started_at': now,
        'completed_at': now,
        'total_count': checks.length,
        'present_count': present,
        'missing_count': missing,
      });

      for (final entry in checks.entries) {
        await txn.insert('inventory_checks', {
          'session_id': sessionId,
          'item_id': entry.key,
          'present': entry.value ? 1 : 0,
        });
      }

      return sessionId;
    });
  }

  Future<Map<String, int>> getSummary() async {
    final db = await database;
    final itemCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM items'),
        ) ??
        0;
    final locationCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM locations'),
        ) ??
        0;
    final inventoryCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM inventory_sessions'),
        ) ??
        0;

    return {
      'items': itemCount,
      'locations': locationCount,
      'inventories': inventoryCount,
    };
  }
}
