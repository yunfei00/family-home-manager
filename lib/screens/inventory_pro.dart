import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models.dart';
import 'qr_scanner_page.dart';

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late Future<_InventoryOverview> _overview;

  @override
  void initState() {
    super.initState();
    _overview = _load();
  }

  Future<_InventoryOverview> _load() async {
    final locations = await AppDatabase.instance.getLocations();
    final counts = await AppDatabase.instance.getItemCountsByLocation();
    final sessions = await AppDatabase.instance.getRecentInventorySessions(
      limit: 3,
    );
    return _InventoryOverview(locations, counts, sessions);
  }

  void _reload() {
    setState(() {
      _overview = _load();
    });
  }

  Future<void> _startInventory(LocationNode location) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InventoryDetailPage(location: location),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _scanInventory() async {
    final location = await Navigator.of(context).push<LocationNode>(
      MaterialPageRoute(
        builder: (_) => const QrScannerPage(title: '扫描要盘库的位置'),
      ),
    );
    if (location == null || !mounted) return;
    await _startInventory(location);
  }

  Future<void> _showHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InventoryHistoryPage()),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_InventoryOverview>(
      future: _overview,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final overview = snapshot.data!;
        final usable = overview.locations
            .where((location) => (overview.counts[location.id] ?? 0) > 0)
            .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _scanInventory,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('扫码盘库'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('盘库历史'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '选择位置',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (usable.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text('还不能盘库'),
                  subtitle: Text('先添加位置和物品，然后按位置盘点。'),
                ),
              )
            else
              for (final location in usable)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.fact_check_outlined),
                    ),
                    title: Text(location.path),
                    subtitle:
                        Text('${overview.counts[location.id] ?? 0} 种物品'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _startInventory(location),
                  ),
                ),
            if (overview.sessions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                '最近盘库',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final session in overview.sessions)
                _SessionCard(
                  session: session,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            InventoryReportPage(session: session),
                      ),
                    );
                  },
                ),
            ],
          ],
        );
      },
    );
  }
}

class _InventoryOverview {
  const _InventoryOverview(
    this.locations,
    this.counts,
    this.sessions,
  );

  final List<LocationNode> locations;
  final Map<int, int> counts;
  final List<InventorySessionSummary> sessions;
}

class InventoryDetailPage extends StatefulWidget {
  const InventoryDetailPage({
    super.key,
    required this.location,
  });

  final LocationNode location;

  @override
  State<InventoryDetailPage> createState() => _InventoryDetailPageState();
}

class _InventoryDetailPageState extends State<InventoryDetailPage> {
  late Future<_InventoryDetailData> _data;

  final Map<int, String> _statuses = {};
  final Map<int, int?> _actualLocations = {};
  final List<UnexpectedInventoryItem> _unexpected = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_InventoryDetailData> _load() async {
    final items =
        await AppDatabase.instance.getItemsAtLocation(widget.location.id);
    final locations = await AppDatabase.instance.getLocations();
    return _InventoryDetailData(items, locations);
  }

  Future<void> _addUnexpected() async {
    final result = await showDialog<UnexpectedInventoryItem>(
      context: context,
      builder: (_) => const _UnexpectedItemDialog(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _unexpected.add(result);
    });
  }

  bool _canSubmit(List<HomeItem> items) {
    for (final item in items) {
      final status = _statuses[item.id] ?? 'present';
      if (status == 'misplaced' && _actualLocations[item.id] == null) {
        return false;
      }
    }
    return true;
  }

  Future<void> _submit(List<HomeItem> items) async {
    if (!_canSubmit(items)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标记为“在别处”的物品需要选择实际位置。')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final statuses = <int, String>{
        for (final item in items)
          item.id: _statuses[item.id] ?? 'present',
      };

      final sessionId =
          await AppDatabase.instance.createInventoryProSession(
        locationId: widget.location.id,
        statuses: statuses,
        actualLocations: _actualLocations,
        unexpectedItems: _unexpected,
      );

      final sessions =
          await AppDatabase.instance.getRecentInventorySessions(limit: 50);
      final session = sessions.firstWhere(
        (value) => value.id == sessionId,
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => InventoryReportPage(session: session),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('盘库')),
      body: FutureBuilder<_InventoryDetailData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;

          return Column(
            children: [
              ListTile(
                title: Text(widget.location.path),
                subtitle: const Text(
                  '逐项确认：在这里 / 缺失 / 实际在别处；也可以登记现场发现的新物品。',
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  children: [
                    for (final item in data.items)
                      _InventoryItemCard(
                        item: item,
                        locations: data.locations,
                        currentLocationId: widget.location.id,
                        status: _statuses[item.id] ?? 'present',
                        actualLocationId: _actualLocations[item.id],
                        onStatusChanged: (status) {
                          setState(() {
                            _statuses[item.id] = status;
                            if (status != 'misplaced') {
                              _actualLocations[item.id] = null;
                            }
                          });
                        },
                        onActualLocationChanged: (locationId) {
                          setState(() {
                            _actualLocations[item.id] = locationId;
                          });
                        },
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _addUnexpected,
                      icon: const Icon(Icons.add),
                      label: const Text('发现新物品'),
                    ),
                    if (_unexpected.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '本次发现的新物品',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (var index = 0;
                          index < _unexpected.length;
                          index++)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.new_releases_outlined),
                            title: Text(_unexpected[index].name),
                            subtitle: Text(
                              _unexpected[index].category.isEmpty
                                  ? '未分类'
                                  : _unexpected[index].category,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_formatQuantity(_unexpected[index].quantity)} ${_unexpected[index].unit}',
                                ),
                                IconButton(
                                  tooltip: '移除',
                                  onPressed: () {
                                    setState(() {
                                      _unexpected.removeAt(index);
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _saving ? null : () => _submit(data.items),
                    icon: const Icon(Icons.done_all),
                    label: Text(_saving ? '保存中…' : '完成盘库并生成报告'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InventoryDetailData {
  const _InventoryDetailData(this.items, this.locations);

  final List<HomeItem> items;
  final List<LocationNode> locations;
}

class _InventoryItemCard extends StatelessWidget {
  const _InventoryItemCard({
    required this.item,
    required this.locations,
    required this.currentLocationId,
    required this.status,
    required this.actualLocationId,
    required this.onStatusChanged,
    required this.onActualLocationChanged,
  });

  final HomeItem item;
  final List<LocationNode> locations;
  final int currentLocationId;
  final String status;
  final int? actualLocationId;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<int?> onActualLocationChanged;

  @override
  Widget build(BuildContext context) {
    final otherLocations = locations
        .where((location) => location.id != currentLocationId)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${_formatQuantity(item.quantity)} ${item.unit}'),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'present',
                  icon: Icon(Icons.check_circle_outline),
                  label: Text('在这里'),
                ),
                ButtonSegment(
                  value: 'missing',
                  icon: Icon(Icons.help_outline),
                  label: Text('缺失'),
                ),
                ButtonSegment(
                  value: 'misplaced',
                  icon: Icon(Icons.drive_file_move_outline),
                  label: Text('在别处'),
                ),
              ],
              selected: {status},
              onSelectionChanged: (values) {
                onStatusChanged(values.first);
              },
            ),
            if (status == 'misplaced') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: actualLocationId,
                decoration: const InputDecoration(
                  labelText: '实际找到的位置',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final location in otherLocations)
                    DropdownMenuItem(
                      value: location.id,
                      child: Text(
                        location.path,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onActualLocationChanged,
              ),
              const SizedBox(height: 6),
              const Text(
                '完成盘库后，系统会把该物品的位置自动更新到这里。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnexpectedItemDialog extends StatefulWidget {
  const _UnexpectedItemDialog();

  @override
  State<_UnexpectedItemDialog> createState() => _UnexpectedItemDialogState();
}

class _UnexpectedItemDialogState extends State<_UnexpectedItemDialog> {
  final _name = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unit = TextEditingController(text: '个');
  final _category = TextEditingController(text: '盘库新增');

  void _submit() {
    final name = _name.text.trim();
    final quantity = double.tryParse(_quantity.text.trim());
    if (name.isEmpty || quantity == null || quantity <= 0) return;

    Navigator.of(context).pop(
      UnexpectedInventoryItem(
        name: name,
        quantity: quantity,
        unit: _unit.text.trim().isEmpty ? '个' : _unit.text.trim(),
        category: _category.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('发现新物品'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: '分类'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '数量'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: '单位'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('加入本次盘库'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    _category.dispose();
    super.dispose();
  }
}

class InventoryHistoryPage extends StatefulWidget {
  const InventoryHistoryPage({super.key});

  @override
  State<InventoryHistoryPage> createState() => _InventoryHistoryPageState();
}

class _InventoryHistoryPageState extends State<InventoryHistoryPage> {
  late Future<List<InventorySessionSummary>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = AppDatabase.instance.getRecentInventorySessions(limit: 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('盘库历史')),
      body: FutureBuilder<List<InventorySessionSummary>>(
        future: _sessions,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return const Center(child: Text('还没有盘库记录'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return _SessionCard(
                session: session,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          InventoryReportPage(session: session),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onTap,
  });

  final InventorySessionSummary session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = session.completedAt.toLocal();

    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
        title: Text(session.locationPath),
        subtitle: Text(
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}\n'
          '在：${session.presentCount}  缺失：${session.missingCount}  '
          '在别处：${session.misplacedCount}  新增：${session.unexpectedCount}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class InventoryReportPage extends StatefulWidget {
  const InventoryReportPage({
    super.key,
    required this.session,
  });

  final InventorySessionSummary session;

  @override
  State<InventoryReportPage> createState() => _InventoryReportPageState();
}

class _InventoryReportPageState extends State<InventoryReportPage> {
  late Future<_InventoryReportData> _report;

  @override
  void initState() {
    super.initState();
    _report = _load();
  }

  Future<_InventoryReportData> _load() async {
    final lines = await AppDatabase.instance.getInventoryReportLines(
      widget.session.id,
    );
    final unexpected =
        await AppDatabase.instance.getInventoryUnexpectedItems(
      widget.session.id,
    );
    return _InventoryReportData(lines, unexpected);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return Scaffold(
      appBar: AppBar(title: const Text('盘库报告')),
      body: FutureBuilder<_InventoryReportData>(
        future: _report,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final issues = data.lines
              .where((line) => line.status != 'present')
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                session.locationPath,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountChip(label: '在这里', value: session.presentCount),
                  _CountChip(label: '缺失', value: session.missingCount),
                  _CountChip(label: '在别处', value: session.misplacedCount),
                  _CountChip(label: '新增', value: session.unexpectedCount),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '差异',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (issues.isEmpty && data.unexpected.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('本次盘库没有差异'),
                  ),
                ),
              for (final line in issues)
                Card(
                  child: ListTile(
                    leading: Icon(
                      line.status == 'missing'
                          ? Icons.help_outline
                          : Icons.drive_file_move_outline,
                    ),
                    title: Text(line.itemName),
                    subtitle: line.status == 'missing'
                        ? const Text('缺失')
                        : Text(
                            '实际位置：${line.actualLocationPath ?? '未记录'}',
                          ),
                  ),
                ),
              for (final item in data.unexpected)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.new_releases_outlined),
                    title: Text(item.name),
                    subtitle: Text('盘库时新发现并加入当前位置'),
                    trailing: Text(
                      '${_formatQuantity(item.quantity)} ${item.unit}',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InventoryReportData {
  const _InventoryReportData(this.lines, this.unexpected);

  final List<InventoryReportLine> lines;
  final List<InventoryUnexpectedRecord> unexpected;
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $value'));
  }
}
