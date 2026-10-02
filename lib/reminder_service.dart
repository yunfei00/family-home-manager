import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_database.dart';
import 'models.dart';

class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.expiryEnabled,
    required this.lowStockEnabled,
    required this.syncConflictEnabled,
  });

  final bool enabled;
  final bool expiryEnabled;
  final bool lowStockEnabled;
  final bool syncConflictEnabled;

  ReminderSettings copyWith({
    bool? enabled,
    bool? expiryEnabled,
    bool? lowStockEnabled,
    bool? syncConflictEnabled,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      expiryEnabled: expiryEnabled ?? this.expiryEnabled,
      lowStockEnabled: lowStockEnabled ?? this.lowStockEnabled,
      syncConflictEnabled: syncConflictEnabled ?? this.syncConflictEnabled,
    );
  }
}

class ReminderSummary {
  const ReminderSummary({
    required this.notificationsEnabled,
    required this.lowStockCount,
    required this.expiringSoonCount,
    required this.expiredCount,
    required this.scheduledCount,
  });

  final bool notificationsEnabled;
  final int lowStockCount;
  final int expiringSoonCount;
  final int expiredCount;
  final int scheduledCount;
}

class ExpiryReminderPlan {
  const ExpiryReminderPlan({
    required this.id,
    required this.itemId,
    required this.daysBefore,
    required this.triggerAt,
    required this.title,
    required this.body,
  });

  final int id;
  final int itemId;
  final int daysBefore;
  final DateTime triggerAt;
  final String title;
  final String body;
}

List<ExpiryReminderPlan> buildExpiryReminderPlans({
  required HomeItem item,
  required DateTime now,
}) {
  final expiry = item.expiryDate;
  if (expiry == null) return const <ExpiryReminderPlan>[];

  const daysList = <int>[30, 7, 1, 0];
  final plans = <ExpiryReminderPlan>[];

  for (var index = 0; index < daysList.length; index++) {
    final days = daysList[index];
    final reminderDay = DateTime(
      expiry.year,
      expiry.month,
      expiry.day,
      9,
    ).subtract(Duration(days: days));

    if (!reminderDay.isAfter(now)) continue;

    final date =
        '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-'
        '${expiry.day.toString().padLeft(2, '0')}';
    final timing = switch (days) {
      30 => '30 天后到期',
      7 => '7 天后到期',
      1 => '明天到期',
      _ => '今天到期',
    };

    plans.add(
      ExpiryReminderPlan(
        id: 100000 + item.id * 10 + index,
        itemId: item.id,
        daysBefore: days,
        triggerAt: reminderDay,
        title: '保质期提醒 · $timing',
        body: '${item.name} 将于 $date 到期，位置：${item.locationPath}',
      ),
    );
  }

  return plans;
}

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  static const MethodChannel _channel =
      MethodChannel('family_home_manager/reminders');

  static const _enabledKey = 'reminder_enabled';
  static const _expiryKey = 'reminder_expiry_enabled';
  static const _lowStockKey = 'reminder_low_stock_enabled';
  static const _syncConflictKey = 'reminder_sync_conflict_enabled';
  static const _scheduledIdsKey = 'reminder_scheduled_ids';
  static const _lastLowStockNoticeKey = 'reminder_last_low_stock_notice';
  static const _lastExpiryNoticeKey = 'reminder_last_expiry_notice';

  Future<ReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return ReminderSettings(
      enabled: prefs.getBool(_enabledKey) ?? true,
      expiryEnabled: prefs.getBool(_expiryKey) ?? true,
      lowStockEnabled: prefs.getBool(_lowStockKey) ?? true,
      syncConflictEnabled: prefs.getBool(_syncConflictKey) ?? true,
    );
  }

  Future<void> saveSettings(ReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, settings.enabled);
    await prefs.setBool(_expiryKey, settings.expiryEnabled);
    await prefs.setBool(_lowStockKey, settings.lowStockEnabled);
    await prefs.setBool(_syncConflictKey, settings.syncConflictEnabled);

    if (!settings.enabled || !settings.expiryEnabled) {
      await _cancelExpirySchedules();
    } else {
      await _refreshExpirySchedules();
    }
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod<bool>('requestPermission');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return notificationsEnabled();
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> notificationsEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('areNotificationsEnabled') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> testNotification() async {
    await _showNow(
      id: 900001,
      title: '家庭管理提醒测试',
      body: '系统通知已经可以正常工作。',
    );
  }

  Future<ReminderSummary> refreshAndNotify() async {
    final settings = await loadSettings();
    final enabled = await notificationsEnabled();

    final lowStock = await AppDatabase.instance.getLowStockItems();
    final expiring = await AppDatabase.instance.getExpiringItems(withinDays: 30);
    final now = DateTime.now();
    final expired = expiring
        .where((item) => item.expiryDate?.isBefore(now) == true)
        .length;

    var scheduledCount = 0;
    if (!settings.enabled) {
      await _cancelExpirySchedules();
    } else {
      if (settings.expiryEnabled) {
        scheduledCount = await _refreshExpirySchedules();
        if (enabled) {
          await _notifyCurrentExpiry(expiring, now);
        }
      } else {
        await _cancelExpirySchedules();
      }

      if (settings.lowStockEnabled && enabled) {
        await _notifyLowStock(lowStock, now);
      }
    }

    return ReminderSummary(
      notificationsEnabled: enabled,
      lowStockCount: lowStock.length,
      expiringSoonCount: expiring.length - expired,
      expiredCount: expired,
      scheduledCount: scheduledCount,
    );
  }

  Future<void> showSyncConflict(String message) async {
    final settings = await loadSettings();
    if (!settings.enabled || !settings.syncConflictEnabled) return;
    if (!await notificationsEnabled()) return;

    await _showNow(
      id: 900003,
      title: '家庭数据同步冲突',
      body: message,
    );
  }

  Future<int> _refreshExpirySchedules() async {
    await _cancelExpirySchedules();

    final items = await AppDatabase.instance.getItems();
    final now = DateTime.now();
    final plans = <ExpiryReminderPlan>[
      for (final item in items)
        ...buildExpiryReminderPlans(item: item, now: now),
    ];

    final scheduledIds = <String>[];
    for (final plan in plans) {
      final scheduled = await _schedule(plan);
      if (scheduled) {
        scheduledIds.add(plan.id.toString());
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_scheduledIdsKey, scheduledIds);
    return scheduledIds.length;
  }

  Future<void> _cancelExpirySchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final rawIds = prefs.getStringList(_scheduledIdsKey) ?? const <String>[];
    final ids = rawIds
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);

    if (ids.isNotEmpty && Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('cancelMany', {'ids': ids});
      } on MissingPluginException {
        // Android bridge is unavailable in non-app test environments.
      }
    }
    await prefs.remove(_scheduledIdsKey);
  }

  Future<bool> _schedule(ExpiryReminderPlan plan) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('schedule', {
            'id': plan.id,
            'triggerAt': plan.triggerAt.millisecondsSinceEpoch,
            'title': plan.title,
            'body': plan.body,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _notifyLowStock(
    List<HomeItem> lowStock,
    DateTime now,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (lowStock.isEmpty) {
      await prefs.remove(_lastLowStockNoticeKey);
      return;
    }

    final ids = [...lowStock]..sort((a, b) => a.id.compareTo(b.id));
    final day = _dayKey(now);
    final signature =
        '$day|${ids.map((item) => '${item.id}:${item.quantity}').join(',')}';

    if (prefs.getString(_lastLowStockNoticeKey) == signature) return;

    final names = ids.take(3).map((item) => item.name).join('、');
    final extra = ids.length > 3 ? '等 ${ids.length} 项' : '';
    await _showNow(
      id: 900002,
      title: '家庭库存不足',
      body: '$names$extra 已达到最低库存，可以准备补货。',
    );
    await prefs.setString(_lastLowStockNoticeKey, signature);
  }

  Future<void> _notifyCurrentExpiry(
    List<HomeItem> expiring,
    DateTime now,
  ) async {
    final urgent = expiring.where((item) {
      final expiry = item.expiryDate;
      if (expiry == null) return false;
      return expiry.difference(now).inDays <= 7;
    }).toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));

    final prefs = await SharedPreferences.getInstance();
    if (urgent.isEmpty) {
      await prefs.remove(_lastExpiryNoticeKey);
      return;
    }

    final day = _dayKey(now);
    final signature = '$day|${urgent.map((item) => item.id).join(',')}';
    if (prefs.getString(_lastExpiryNoticeKey) == signature) return;

    final expired =
        urgent.where((item) => item.expiryDate!.isBefore(now)).length;
    final names = urgent.take(3).map((item) => item.name).join('、');
    final suffix = expired > 0
        ? '；其中 $expired 项已经过期'
        : '；请留意近期到期';

    await _showNow(
      id: 900004,
      title: '保质期提醒',
      body: '$names$suffix',
    );
    await prefs.setString(_lastExpiryNoticeKey, signature);
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('showNow', {
        'id': id,
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      // Ignore when running outside the Android app.
    }
  }

  String _dayKey(DateTime value) {
    return '${value.year}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}
