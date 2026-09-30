import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/models.dart';

void main() {
  test('home item reads stock fields', () {
    final item = HomeItem.fromMap({
      'id': 1,
      'name': '牙膏',
      'category': '日用品',
      'kind': 'quantity',
      'location_id': 2,
      'location_path': '我的家 / 卫生间',
      'quantity': 1,
      'unit': '支',
      'notes': '',
      'photo_path': null,
      'barcode': null,
      'is_consumable': 1,
      'minimum_quantity': 2,
      'expiry_date': '2026-10-15T23:59:59.000',
    });

    expect(item.isConsumable, isTrue);
    expect(item.minimumQuantity, 2);
    expect(item.expiryDate, isNotNull);
    expect(item.expiryDate!.year, 2026);
  });

  test('home item defaults stock management off', () {
    final item = HomeItem.fromMap({
      'id': 2,
      'name': '螺丝刀',
      'category': '工具',
      'kind': 'single',
      'location_id': 3,
      'location_path': '我的家 / 工具柜',
      'quantity': 1,
      'unit': '把',
      'notes': '',
    });

    expect(item.isConsumable, isFalse);
    expect(item.minimumQuantity, isNull);
    expect(item.expiryDate, isNull);
  });

  test('shopping list entry maps persisted state', () {
    final entry = ShoppingListEntry.fromMap({
      'id': 8,
      'item_id': 1,
      'name': '牙膏',
      'quantity': 2,
      'unit': '支',
      'checked': 1,
      'created_at': '2026-09-30T22:00:00.000',
    });

    expect(entry.itemId, 1);
    expect(entry.checked, isTrue);
    expect(entry.quantity, 2);
  });
}
