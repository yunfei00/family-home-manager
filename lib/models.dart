import 'qr.dart';

class LocationNode {
  const LocationNode({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.code,
    this.parentId,
  });

  final int id;
  final String name;
  final String path;
  final String type;
  final String code;
  final int? parentId;

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
    );
  }
}
