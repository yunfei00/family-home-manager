import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/models.dart';
import 'package:family_home_manager/reminder_service.dart';

HomeItem _item(DateTime expiry) {
  return HomeItem(
    id: 12,
    name: '儿童退热贴',
    category: '医药',
    kind: 'quantity',
    locationId: 2,
    locationPath: '我的家 / 医药柜',
    quantity: 2,
    unit: '盒',
    notes: '',
    expiryDate: expiry,
  );
}

void main() {
  test('builds four future expiry reminders for distant expiry', () {
    final now = DateTime(2026, 10, 2, 8);
    final plans = buildExpiryReminderPlans(
      item: _item(DateTime(2026, 12, 20, 23, 59, 59)),
      now: now,
    );

    expect(plans.map((plan) => plan.daysBefore), [30, 7, 1, 0]);
    expect(plans.first.triggerAt.hour, 9);
    expect(plans.first.body, contains('儿童退热贴'));
  });

  test('skips reminder times that have already passed', () {
    final now = DateTime(2026, 10, 2, 12);
    final plans = buildExpiryReminderPlans(
      item: _item(DateTime(2026, 10, 3, 23, 59, 59)),
      now: now,
    );

    expect(plans.length, 1);
    expect(plans.single.daysBefore, 0);
  });

  test('item without expiry creates no schedule', () {
    const item = HomeItem(
      id: 1,
      name: '螺丝刀',
      category: '工具',
      kind: 'single',
      locationId: 1,
      locationPath: '我的家 / 工具柜',
      quantity: 1,
      unit: '把',
      notes: '',
    );

    expect(
      buildExpiryReminderPlans(
        item: item,
        now: DateTime(2026, 10, 2),
      ),
      isEmpty,
    );
  });

  test('reminder ids are deterministic per item and threshold', () {
    final now = DateTime(2026, 10, 2);
    final first = buildExpiryReminderPlans(
      item: _item(DateTime(2026, 12, 20)),
      now: now,
    );
    final second = buildExpiryReminderPlans(
      item: _item(DateTime(2026, 12, 20)),
      now: now,
    );

    expect(
      first.map((plan) => plan.id).toList(),
      second.map((plan) => plan.id).toList(),
    );
  });
}
