import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/fast_entry_parser.dart';

void main() {
  test('parses comma separated items and units', () {
    final items = parseFastEntries('牙膏3支，口罩2盒，体温计1个');

    expect(items.length, 3);
    expect(items[0].name, '牙膏');
    expect(items[0].quantity, 3);
    expect(items[0].unit, '支');
    expect(items[1].name, '口罩');
    expect(items[1].quantity, 2);
    expect(items[1].unit, '盒');
  });

  test('parses Chinese numbers', () {
    final items = parseFastEntries('湿巾两包，垃圾袋十二袋');

    expect(items[0].quantity, 2);
    expect(items[1].quantity, 12);
  });

  test('defaults an item without quantity to one', () {
    final items = parseFastEntries('体温计');

    expect(items.single.name, '体温计');
    expect(items.single.quantity, 1);
    expect(items.single.unit, '个');
  });

  test('supports newline separated batch input', () {
    final items = parseFastEntries('螺丝刀1把\n电池4节');

    expect(items.length, 2);
    expect(items[0].unit, '把');
    expect(items[1].name, '电池4节');
  });
}
