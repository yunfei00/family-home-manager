import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/models.dart';

void main() {
  test('LocationNode can be created from a database row', () {
    final location = LocationNode.fromMap({
      'id': 2,
      'name': '客厅',
      'path': '我的家 / 客厅',
      'type': 'room',
      'parent_id': 1,
    });

    expect(location.id, 2);
    expect(location.name, '客厅');
    expect(location.path, '我的家 / 客厅');
  });

  test('HomeItem normalizes numeric quantity', () {
    final item = HomeItem.fromMap({
      'id': 1,
      'name': '体温计',
      'category': '医药',
      'kind': 'single',
      'location_id': 2,
      'location_path': '我的家 / 客厅',
      'quantity': 1,
      'unit': '个',
      'notes': '',
    });

    expect(item.quantity, 1.0);
    expect(item.locationId, 2);
  });
}
