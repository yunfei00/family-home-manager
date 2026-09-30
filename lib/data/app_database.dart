import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../qr.dart';

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
      version: 6,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );

    _database = db;
    return db;
  }

  Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        type TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        code TEXT UNIQUE,
        photo_path TEXT,
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
        photo_path TEXT,
        barcode TEXT,
        is_consumable INTEGER NOT NULL DEFAULT 0,
        minimum_quantity REAL,
        expiry_date TEXT,
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
        missing_count INTEGER NOT NULL,
        misplaced_count INTEGER NOT NULL DEFAULT 0,
        unexpected_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE TABLE inventory_checks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        present INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'present',
        actual_location_id INTEGER,
        FOREIGN KEY(session_id) REFERENCES inventory_sessions(id),
        FOREIGN KEY(item_id) REFERENCES items(id),
        FOREIGN KEY(actual_location_id) REFERENCES locations(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE inventory_unexpected_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT '个',
        category TEXT NOT NULL DEFAULT '',
        created_item_id INTEGER,
        FOREIGN KEY(session_id) REFERENCES inventory_sessions(id),
        FOREIGN KEY(created_item_id) REFERENCES items(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE shopping_list (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER,
        name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT '个',
        checked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(item_id) REFERENCES items(id)
      )
    ''');

    await _createMovementTable(database);

    final now = DateTime.now().toIso8601String();
    final rootId = await database.insert('locations', {
      'name': '我的家',
      'parent_id': null,
      'type': 'home',
      'path': '我的家',
      'code': null,
      'created_at': now,
    });
    await database.update(
      'locations',
      {'code': locationCodeFromId(rootId)},
      where: 'id = ?',
      whereArgs: [rootId],
    );
  }

  Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await database.execute('ALTER TABLE locations ADD COLUMN code TEXT');
      final rows = await database.query('locations', columns: ['id']);
      for (final row in rows) {
        final id = row['id'] as int;
        await database.update(
          'locations',
          {'code': locationCodeFromId(id)},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await database.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_locations_code ON locations(code)',
      );
      await _createMovementTable(database);
    }
    if (oldVersion < 3) {
      await database.execute('ALTER TABLE locations ADD COLUMN photo_path TEXT');
      await database.execute('ALTER TABLE items ADD COLUMN photo_path TEXT');
    }
    if (oldVersion < 4) {
      await database.execute('ALTER TABLE items ADD COLUMN barcode TEXT');
      await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_items_barcode ON items(barcode)',
      );
    }
    if (oldVersion < 5) {
      await database.execute(
        'ALTER TABLE inventory_sessions ADD COLUMN misplaced_count INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'ALTER TABLE inventory_sessions ADD COLUMN unexpected_count INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        "ALTER TABLE inventory_checks ADD COLUMN status TEXT NOT NULL DEFAULT 'present'",
      );
      await database.execute(
        'ALTER TABLE inventory_checks ADD COLUMN actual_location_id INTEGER',
      );
      await database.execute(
        "UPDATE inventory_checks SET status = CASE WHEN present = 1 THEN 'present' ELSE 'missing' END",
      );
      await database.execute('''
        CREATE TABLE IF NOT EXISTS inventory_unexpected_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          quantity REAL NOT NULL DEFAULT 1,
          unit TEXT NOT NULL DEFAULT '个',
          category TEXT NOT NULL DEFAULT '',
          created_item_id INTEGER,
          FOREIGN KEY(session_id) REFERENCES inventory_sessions(id),
          FOREIGN KEY(created_item_id) REFERENCES items(id)
        )
      ''');
    }
    if (oldVersion < 6) {
      await database.execute(
        'ALTER TABLE items ADD COLUMN is_consumable INTEGER NOT NULL DEFAULT 0',
      );
      await database.execute(
        'ALTER TABLE items ADD COLUMN minimum_quantity REAL',
      );
      await database.execute(
        'ALTER TABLE items ADD COLUMN expiry_date TEXT',
      );
      await database.execute('''
        CREATE TABLE IF NOT EXISTS shopping_list (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER,
          name TEXT NOT NULL,
          quantity REAL NOT NULL DEFAULT 1,
          unit TEXT NOT NULL DEFAULT '个',
          checked INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY(item_id) REFERENCES items(id)
        )
      ''');
      await database.execute(
        'CREATE INDEX IF NOT EXISTS idx_shopping_list_checked ON shopping_list(checked)',
      );
    }
  }

  Future<void> _createMovementTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS item_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        from_location_id INTEGER NOT NULL,
        to_location_id INTEGER NOT NULL,
        moved_at TEXT NOT NULL,
        FOREIGN KEY(item_id) REFERENCES items(id),
        FOREIGN KEY(from_location_id) REFERENCES locations(id),
        FOREIGN KEY(to_location_id) REFERENCES locations(id)
      )
    ''');
  }

  Future<List<LocationNode>> getLocations() async {
    final db = await database;
    final rows = await db.query('locations', orderBy: 'path ASC');
    return rows.map(LocationNode.fromMap).toList();
  }

  Future<LocationNode?> getLocationById(int id) async {
    final db = await database;
    final rows = await db.query(
      'locations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocationNode.fromMap(rows.first);
  }

  Future<LocationNode?> getLocationByCode(String code) async {
    final db = await database;
    final rows = await db.query(
      'locations',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocationNode.fromMap(rows.first);
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

    return db.transaction((txn) async {
      final id = await txn.insert('locations', {
        'name': cleanName,
        'parent_id': parentId,
        'type': type,
        'path': '$parentPath / $cleanName',
        'code': null,
        'created_at': now,
      });
      await txn.update(
        'locations',
        {'code': locationCodeFromId(id)},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    });
  }

  Future<List<HomeItem>> getItems({String query = ''}) async {
    final db = await database;
    final clean = query.trim();
    final where = clean.isEmpty
        ? null
        : '(i.name LIKE ? OR i.category LIKE ? OR i.notes LIKE ? OR i.barcode LIKE ?)';
    final args = clean.isEmpty
        ? null
        : List<Object?>.filled(4, '%$clean%');

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
    String? photoPath,
    String? barcode,
    bool isConsumable = false,
    double? minimumQuantity,
    DateTime? expiryDate,
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
      'photo_path': photoPath,
      'barcode': barcode?.trim().isEmpty == true ? null : barcode?.trim(),
      'is_consumable': isConsumable ? 1 : 0,
      'minimum_quantity': minimumQuantity,
      'expiry_date': expiryDate?.toIso8601String(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<int>> addItemsBatch({
    required List<({
      String name,
      double quantity,
      String unit,
    })> items,
    required String category,
    required int locationId,
    String kind = 'quantity',
  }) async {
    if (items.isEmpty) return const <int>[];

    final db = await database;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final ids = <int>[];

      for (final item in items) {
        final id = await txn.insert('items', {
          'name': item.name.trim(),
          'category': category.trim(),
          'kind': kind,
          'location_id': locationId,
          'quantity': item.quantity,
          'unit': item.unit.trim().isEmpty ? '个' : item.unit.trim(),
          'notes': '',
          'photo_path': null,
          'barcode': null,
          'is_consumable': 0,
          'minimum_quantity': null,
          'expiry_date': null,
          'created_at': now,
          'updated_at': now,
        });
        ids.add(id);
      }

      return ids;
    });
  }

  Future<HomeItem?> getItemById(int id) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT i.*, l.path AS location_path
      FROM items i
      JOIN locations l ON l.id = i.location_id
      WHERE i.id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return HomeItem.fromMap(rows.first);
  }

  Future<void> updateItemPhoto(int itemId, String? photoPath) async {
    final db = await database;
    await db.update(
      'items',
      {
        'photo_path': photoPath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> updateLocationPhoto(int locationId, String? photoPath) async {
    final db = await database;
    await db.update(
      'locations',
      {'photo_path': photoPath},
      where: 'id = ?',
      whereArgs: [locationId],
    );
  }

  Future<void> moveItem({
    required int itemId,
    required int toLocationId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final itemRows = await txn.query(
        'items',
        columns: ['location_id'],
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (itemRows.isEmpty) {
        throw StateError('Item not found');
      }

      final fromLocationId = itemRows.first['location_id'] as int;
      if (fromLocationId == toLocationId) return;

      final now = DateTime.now().toIso8601String();
      await txn.update(
        'items',
        {
          'location_id': toLocationId,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );
      await txn.insert('item_movements', {
        'item_id': itemId,
        'from_location_id': fromLocationId,
        'to_location_id': toLocationId,
        'moved_at': now,
      });
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

  Future<int> createInventoryProSession({
    required int locationId,
    required Map<int, String> statuses,
    required Map<int, int?> actualLocations,
    required List<UnexpectedInventoryItem> unexpectedItems,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final present =
          statuses.values.where((value) => value == 'present').length;
      final missing =
          statuses.values.where((value) => value == 'missing').length;
      final misplaced =
          statuses.values.where((value) => value == 'misplaced').length;

      final sessionId = await txn.insert('inventory_sessions', {
        'location_id': locationId,
        'started_at': now,
        'completed_at': now,
        'total_count': statuses.length,
        'present_count': present,
        'missing_count': missing,
        'misplaced_count': misplaced,
        'unexpected_count': unexpectedItems.length,
      });

      for (final entry in statuses.entries) {
        final status = entry.value;
        final actualLocationId = actualLocations[entry.key];

        await txn.insert('inventory_checks', {
          'session_id': sessionId,
          'item_id': entry.key,
          'present': status == 'present' ? 1 : 0,
          'status': status,
          'actual_location_id': actualLocationId,
        });

        if (status == 'misplaced' &&
            actualLocationId != null &&
            actualLocationId != locationId) {
          final itemRows = await txn.query(
            'items',
            columns: ['location_id'],
            where: 'id = ?',
            whereArgs: [entry.key],
            limit: 1,
          );
          if (itemRows.isNotEmpty) {
            final fromLocationId = itemRows.first['location_id'] as int;
            if (fromLocationId != actualLocationId) {
              await txn.update(
                'items',
                {
                  'location_id': actualLocationId,
                  'updated_at': now,
                },
                where: 'id = ?',
                whereArgs: [entry.key],
              );
              await txn.insert('item_movements', {
                'item_id': entry.key,
                'from_location_id': fromLocationId,
                'to_location_id': actualLocationId,
                'moved_at': now,
              });
            }
          }
        }
      }

      for (final unexpected in unexpectedItems) {
        final createdItemId = await txn.insert('items', {
          'name': unexpected.name.trim(),
          'category': unexpected.category.trim(),
          'kind': unexpected.quantity == 1 ? 'single' : 'quantity',
          'location_id': locationId,
          'quantity': unexpected.quantity,
          'unit': unexpected.unit.trim().isEmpty ? '个' : unexpected.unit.trim(),
          'notes': '盘库时发现并新增',
          'photo_path': null,
          'barcode': null,
          'created_at': now,
          'updated_at': now,
        });

        await txn.insert('inventory_unexpected_items', {
          'session_id': sessionId,
          'name': unexpected.name.trim(),
          'quantity': unexpected.quantity,
          'unit': unexpected.unit.trim().isEmpty ? '个' : unexpected.unit.trim(),
          'category': unexpected.category.trim(),
          'created_item_id': createdItemId,
        });
      }

      return sessionId;
    });
  }

  Future<List<InventorySessionSummary>> getRecentInventorySessions({
    int limit = 30,
  }) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT s.*, l.path AS location_path
      FROM inventory_sessions s
      JOIN locations l ON l.id = s.location_id
      ORDER BY s.completed_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(InventorySessionSummary.fromMap).toList();
  }

  Future<List<InventoryReportLine>> getInventoryReportLines(
    int sessionId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        c.item_id,
        i.name AS item_name,
        c.present,
        c.status,
        actual.path AS actual_location_path
      FROM inventory_checks c
      JOIN items i ON i.id = c.item_id
      LEFT JOIN locations actual ON actual.id = c.actual_location_id
      WHERE c.session_id = ?
      ORDER BY
        CASE c.status
          WHEN 'missing' THEN 0
          WHEN 'misplaced' THEN 1
          ELSE 2
        END,
        i.name COLLATE NOCASE ASC
      ''',
      [sessionId],
    );
    return rows.map(InventoryReportLine.fromMap).toList();
  }

  Future<List<InventoryUnexpectedRecord>> getInventoryUnexpectedItems(
    int sessionId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'inventory_unexpected_items',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(InventoryUnexpectedRecord.fromMap).toList();
  }

  Future<void> updateStockSettings({
    required int itemId,
    required bool isConsumable,
    double? minimumQuantity,
    DateTime? expiryDate,
  }) async {
    final db = await database;
    await db.update(
      'items',
      {
        'is_consumable': isConsumable ? 1 : 0,
        'minimum_quantity': minimumQuantity,
        'expiry_date': expiryDate?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> setItemQuantity(int itemId, double quantity) async {
    final db = await database;
    await db.update(
      'items',
      {
        'quantity': quantity < 0 ? 0 : quantity,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<List<HomeItem>> getConsumableItems() async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT i.*, l.path AS location_path
      FROM items i
      JOIN locations l ON l.id = i.location_id
      WHERE i.is_consumable = 1
      ORDER BY i.name COLLATE NOCASE ASC
      ''',
    );
    return rows.map(HomeItem.fromMap).toList();
  }

  Future<List<HomeItem>> getLowStockItems() async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT i.*, l.path AS location_path
      FROM items i
      JOIN locations l ON l.id = i.location_id
      WHERE i.is_consumable = 1
        AND i.minimum_quantity IS NOT NULL
        AND i.quantity <= i.minimum_quantity
      ORDER BY (i.minimum_quantity - i.quantity) DESC, i.name COLLATE NOCASE ASC
      ''',
    );
    return rows.map(HomeItem.fromMap).toList();
  }

  Future<List<HomeItem>> getExpiringItems({int withinDays = 30}) async {
    final db = await database;
    final now = DateTime.now();
    final end = now.add(Duration(days: withinDays));
    final rows = await db.rawQuery(
      '''
      SELECT i.*, l.path AS location_path
      FROM items i
      JOIN locations l ON l.id = i.location_id
      WHERE i.expiry_date IS NOT NULL
        AND i.expiry_date <= ?
      ORDER BY i.expiry_date ASC
      ''',
      [end.toIso8601String()],
    );
    return rows.map(HomeItem.fromMap).toList();
  }

  Future<List<ShoppingListEntry>> getShoppingList({
    bool includeChecked = true,
  }) async {
    final db = await database;
    final rows = await db.query(
      'shopping_list',
      where: includeChecked ? null : 'checked = 0',
      orderBy: 'checked ASC, created_at DESC',
    );
    return rows.map(ShoppingListEntry.fromMap).toList();
  }

  Future<int> addShoppingListEntry({
    int? itemId,
    required String name,
    required double quantity,
    required String unit,
  }) async {
    final db = await database;
    return db.insert('shopping_list', {
      'item_id': itemId,
      'name': name.trim(),
      'quantity': quantity <= 0 ? 1 : quantity,
      'unit': unit.trim().isEmpty ? '个' : unit.trim(),
      'checked': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> addLowStockItemToShoppingList(HomeItem item) async {
    final db = await database;
    final existing = await db.query(
      'shopping_list',
      columns: ['id'],
      where: 'item_id = ? AND checked = 0',
      whereArgs: [item.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    final minimum = item.minimumQuantity ?? item.quantity;
    final shortage = minimum - item.quantity;
    await addShoppingListEntry(
      itemId: item.id,
      name: item.name,
      quantity: shortage > 0 ? shortage : 1,
      unit: item.unit,
    );
    return true;
  }

  Future<void> setShoppingListChecked(int id, bool checked) async {
    final db = await database;
    await db.update(
      'shopping_list',
      {'checked': checked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteShoppingListEntry(int id) async {
    final db = await database;
    await db.delete(
      'shopping_list',
      where: 'id = ?',
      whereArgs: [id],
    );
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
