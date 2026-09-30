import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/models.dart';

void main() {
  test('inventory session summary reads discrepancy counts', () {
    final summary = InventorySessionSummary.fromMap({
      'id': 7,
      'location_id': 2,
      'location_path': '我的家 / 客厅 / 玩具箱',
      'completed_at': '2026-09-30T20:00:00.000',
      'total_count': 8,
      'present_count': 5,
      'missing_count': 1,
      'misplaced_count': 1,
      'unexpected_count': 1,
    });

    expect(summary.totalCount, 8);
    expect(summary.presentCount, 5);
    expect(summary.missingCount, 1);
    expect(summary.misplacedCount, 1);
    expect(summary.unexpectedCount, 1);
  });

  test('old inventory check maps boolean present to status', () {
    final line = InventoryReportLine.fromMap({
      'item_id': 1,
      'item_name': '体温计',
      'present': 0,
      'status': null,
      'actual_location_path': null,
    });

    expect(line.status, 'missing');
  });
}
