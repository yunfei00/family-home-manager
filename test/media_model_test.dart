import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/models.dart';

void main() {
  test('item accepts photo path from database row', () {
    final item = HomeItem.fromMap({
      'id': 1,
      'name': '体温计',
      'category': '医药',
      'kind': 'single',
      'location_id': 2,
      'location_path': '我的家 / 医药柜',
      'quantity': 1,
      'unit': '个',
      'notes': '',
      'photo_path': '/data/photos/a.jpg',
    });

    expect(item.photoPath, '/data/photos/a.jpg');
  });

  test('location accepts nullable photo path', () {
    final location = LocationNode.fromMap({
      'id': 3,
      'name': '白色高柜',
      'path': '我的家 / 入户 / 白色高柜',
      'type': 'furniture',
      'code': 'FHM-LOC-000003',
      'parent_id': 2,
      'photo_path': null,
    });

    expect(location.photoPath, isNull);
  });
}
