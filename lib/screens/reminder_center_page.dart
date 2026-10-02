import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models.dart';
import '../reminder_service.dart';

class ReminderCenterPage extends StatefulWidget {
  const ReminderCenterPage({super.key});

  @override
  State<ReminderCenterPage> createState() => _ReminderCenterPageState();
}

class _ReminderCenterPageState extends State<ReminderCenterPage> {
  late Future<_ReminderPageData> _data;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_ReminderPageData> _load() async {
    final settings = await ReminderService.instance.loadSettings();
    final summary = await ReminderService.instance.refreshAndNotify();
    final lowStock = await AppDatabase.instance.getLowStockItems();
    final expiring = await AppDatabase.instance.getExpiringItems(withinDays: 30);
    return _ReminderPageData(
      settings: settings,
      summary: summary,
      lowStock: lowStock,
      expiring: expiring,
    );
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _saveSettings(ReminderSettings settings) async {
    setState(() {
      _busy = true;
    });
    try {
      await ReminderService.instance.saveSettings(settings);
      if (mounted) _reload();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      _busy = true;
    });
    try {
      final enabled = await ReminderService.instance.requestPermission();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '系统通知权限已开启'
                : '已发起通知权限请求；如果仍未开启，请在系统设置中允许通知。',
          ),
        ),
      );
      _reload();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _testNotification() async {
    await ReminderService.instance.testNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已发送一条测试通知')),
    );
  }

  Future<void> _refreshSchedules() async {
    setState(() {
      _busy = true;
    });
    try {
      final summary = await ReminderService.instance.refreshAndNotify();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('提醒已刷新：系统计划 ${summary.scheduledCount} 条'),
        ),
      );
      _reload();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提醒中心')),
      body: FutureBuilder<_ReminderPageData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final settings = data.settings;
          final now = DateTime.now();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        data.summary.notificationsEnabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                      ),
                      title: Text(
                        data.summary.notificationsEnabled
                            ? '系统通知已允许'
                            : '系统通知未开启',
                      ),
                      subtitle: Text(
                        '已计划 ${data.summary.scheduledCount} 条保质期系统提醒',
                      ),
                    ),
                    if (!data.summary.notificationsEnabled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: _busy ? null : _requestPermission,
                            icon: const Icon(Icons.notifications_active_outlined),
                            label: const Text('开启系统通知'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('家庭提醒总开关'),
                subtitle: const Text('关闭后取消保质期系统计划，并停止库存/同步冲突提醒'),
                value: settings.enabled,
                onChanged: _busy
                    ? null
                    : (value) => _saveSettings(
                          settings.copyWith(enabled: value),
                        ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('保质期提醒'),
                subtitle: const Text('提前 30 天、7 天、1 天以及到期当天提醒'),
                value: settings.expiryEnabled,
                onChanged: _busy || !settings.enabled
                    ? null
                    : (value) => _saveSettings(
                          settings.copyWith(expiryEnabled: value),
                        ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('库存不足提醒'),
                subtitle: const Text('达到或低于最低库存时提醒；同一天相同状态不重复打扰'),
                value: settings.lowStockEnabled,
                onChanged: _busy || !settings.enabled
                    ? null
                    : (value) => _saveSettings(
                          settings.copyWith(lowStockEnabled: value),
                        ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同步冲突提醒'),
                subtitle: const Text('两台手机同时修改导致无法自动合并时提醒'),
                value: settings.syncConflictEnabled,
                onChanged: _busy || !settings.enabled
                    ? null
                    : (value) => _saveSettings(
                          settings.copyWith(syncConflictEnabled: value),
                        ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _testNotification,
                      icon: const Icon(Icons.notification_add_outlined),
                      label: const Text('测试通知'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _refreshSchedules,
                      icon: const Icon(Icons.refresh),
                      label: const Text('刷新提醒'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '当前需要关注',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.warning_amber_outlined),
                    label: Text('库存不足 ${data.summary.lowStockCount}'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.event_outlined),
                    label: Text('30天内到期 ${data.summary.expiringSoonCount}'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.event_busy_outlined),
                    label: Text('已过期 ${data.summary.expiredCount}'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (data.lowStock.isNotEmpty) ...[
                Text(
                  '库存不足',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                for (final item in data.lowStock)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(item.name),
                      subtitle: Text(
                        '现有 ${_quantity(item.quantity)} ${item.unit} · '
                        '最低 ${_quantity(item.minimumQuantity ?? 0)} ${item.unit}',
                      ),
                    ),
                  ),
              ],
              if (data.expiring.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  '保质期',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                for (final item in data.expiring)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        item.expiryDate!.isBefore(now)
                            ? Icons.event_busy_outlined
                            : Icons.event_outlined,
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        '${_date(item.expiryDate!)} · ${_expiryText(item, now)}',
                      ),
                    ),
                  ),
              ],
              if (data.lowStock.isEmpty && data.expiring.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('目前没有需要特别关注的库存或保质期项目'),
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                '说明：保质期系统提醒使用 Android 的非精确定时，不需要“精确闹钟”权限。'
                '手机可能因省电策略延后几分钟到更长时间；App 每次打开或回到前台也会重新检查并补充提醒。',
              ),
            ],
          );
        },
      ),
    );
  }

  String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  String _date(DateTime value) {
    return '${value.year}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  String _expiryText(HomeItem item, DateTime now) {
    final expiry = item.expiryDate!;
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(expiry.year, expiry.month, expiry.day);
    final days = target.difference(today).inDays;
    if (days < 0) return '已过期 ${-days} 天';
    if (days == 0) return '今天到期';
    return '$days 天后到期';
  }
}

class _ReminderPageData {
  const _ReminderPageData({
    required this.settings,
    required this.summary,
    required this.lowStock,
    required this.expiring,
  });

  final ReminderSettings settings;
  final ReminderSummary summary;
  final List<HomeItem> lowStock;
  final List<HomeItem> expiring;
}
