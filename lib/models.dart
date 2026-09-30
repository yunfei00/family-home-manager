import 'qr.dart';

class LocationNode {
  const LocationNode({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.code,
    this.parentId,
    this.photoPath,
  });

  final int id;
  final String name;
  final String path;
  final String type;
  final String code;
  final int? parentId;
  final String? photoPath;

  String get qrPayload => buildLocationQrPayload(code);

  factory LocationNode.fromMap(Map<String, Object?> map) {
    final id = map['id'] as int;
    final rawCode = map['code'] as String?;
    return LocationNode(
      id: id,
      name: map['name'] as String,
      path: map['path'] as String,
      type: map['type'] as String,
      code: rawCode == null || rawCode.isEmpty ? locationCodeFromId(id) : rawCode,
      parentId: map['parent_id'] as int?,
      photoPath: map['photo_path'] as String?,
    );
  }
}

class HomeItem {
  const HomeItem({
    required this.id,
    required this.name,
    required this.category,
    required this.kind,
    required this.locationId,
    required this.locationPath,
    required this.quantity,
    required this.unit,
    required this.notes,
    this.photoPath,
    this.barcode,
  });

  final int id;
  final String name;
  final String category;
  final String kind;
  final int locationId;
  final String locationPath;
  final double quantity;
  final String unit;
  final String notes;
  final String? photoPath;
  final String? barcode;

  factory HomeItem.fromMap(Map<String, Object?> map) {
    return HomeItem(
      id: map['id'] as int,
      name: map['name'] as String,
      category: (map['category'] as String?) ?? '',
      kind: (map['kind'] as String?) ?? 'single',
      locationId: map['location_id'] as int,
      locationPath: (map['location_path'] as String?) ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
      unit: (map['unit'] as String?) ?? '个',
      notes: (map['notes'] as String?) ?? '',
      photoPath: map['photo_path'] as String?,
      barcode: map['barcode'] as String?,
    );
  }
}


class InventorySessionSummary {
  const InventorySessionSummary({
    required this.id,
    required this.locationId,
    required this.locationPath,
    required this.completedAt,
    required this.totalCount,
    required this.presentCount,
    required this.missingCount,
    required this.misplacedCount,
    required this.unexpectedCount,
  });

  final int id;
  final int locationId;
  final String locationPath;
  final DateTime completedAt;
  final int totalCount;
  final int presentCount;
  final int missingCount;
  final int misplacedCount;
  final int unexpectedCount;

  factory InventorySessionSummary.fromMap(Map<String, Object?> map) {
    return InventorySessionSummary(
      id: map['id'] as int,
      locationId: map['location_id'] as int,
      locationPath: (map['location_path'] as String?) ?? '',
      completedAt: DateTime.parse(map['completed_at'] as String),
      totalCount: (map['total_count'] as num).toInt(),
      presentCount: (map['present_count'] as num).toInt(),
      missingCount: (map['missing_count'] as num).toInt(),
      misplacedCount: (map['misplaced_count'] as num?)?.toInt() ?? 0,
      unexpectedCount: (map['unexpected_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class InventoryReportLine {
  const InventoryReportLine({
    required this.itemId,
    required this.itemName,
    required this.status,
    this.actualLocationPath,
  });

  final int itemId;
  final String itemName;
  final String status;
  final String? actualLocationPath;

  factory InventoryReportLine.fromMap(Map<String, Object?> map) {
    return InventoryReportLine(
      itemId: map['item_id'] as int,
      itemName: map['item_name'] as String,
      status: (map['status'] as String?) ??
          ((map['present'] as int? ?? 0) == 1 ? 'present' : 'missing'),
      actualLocationPath: map['actual_location_path'] as String?,
    );
  }
}

class UnexpectedInventoryItem {
  const UnexpectedInventoryItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
  });

  final String name;
  final double quantity;
  final String unit;
  final String category;
}

class InventoryUnexpectedRecord {
  const InventoryUnexpectedRecord({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
  });

  final String name;
  final double quantity;
  final String unit;
  final String category;

  factory InventoryUnexpectedRecord.fromMap(Map<String, Object?> map) {
    return InventoryUnexpectedRecord(
      name: map['name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
      category: (map['category'] as String?) ?? '',
    );
  }
}
