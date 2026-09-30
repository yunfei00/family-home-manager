import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models.dart';

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardPage(),
      const ItemsPage(),
      const LocationsPage(),
      const InventoryPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭管理'),
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: '物品'),
          NavigationDestination(icon: Icon(Icons.account_tree_outlined), label: '位置'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: '盘库'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, int>> _summary;

  @override
  void initState() {
    super.initState();
    _summary = AppDatabase.instance.getSummary();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _summary = AppDatabase.instance.getSummary());
        await _summary;
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('我的家', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('先记录位置，再把重要物品放进去。以后找东西、盘库都会更快。'),
          const SizedBox(height: 20),
          FutureBuilder<Map<String, int>>(
            future: _summary,
            builder: (context, snapshot) {
              final data = snapshot.data ??
                  const {'items': 0, 'locations': 0, 'inventories': 0};
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(label: '物品', value: data['items'] ?? 0),
                  _MetricCard(label: '位置', value: data['locations'] ?? 0),
                  _MetricCard(label: '盘库', value: data['inventories'] ?? 0),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Card(
            child: ListTile(
              leading: Icon(Icons.tips_and_updates_outlined),
              title: Text('推荐录入方式'),
              subtitle: Text('重要物品逐件记录；日用品记数量；玩具和衣物按“箱/集合”记录。'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('$value', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _searchController = TextEditingController();
  late Future<List<HomeItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = AppDatabase.instance.getItems();
  }

  void _reload() {
    setState(() {
      _items = AppDatabase.instance.getItems(query: _searchController.text);
    });
  }

  Future<void> _addItem() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddItemPage()),
    );
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: '找东西：体温计、牙膏、螺丝刀……',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _searchController.clear();
                      _reload();
                    },
                    icon: const Icon(Icons.clear),
                  ),
              ],
              onChanged: (_) => _reload(),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<HomeItem>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? const <HomeItem>[];
                if (items.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: '还没有物品',
                    subtitle: '先添加一个重要物品试试。',
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.inventory_2_outlined),
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        '${item.locationPath}\n${item.category.isEmpty ? item.kind : item.category}',
                      ),
                      isThreeLine: true,
                      trailing: Text('${_formatQuantity(item.quantity)} ${item.unit}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('添加物品'),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class AddItemPage extends StatefulWidget {
  const AddItemPage({super.key});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unit = TextEditingController(text: '个');
  final _notes = TextEditingController();

  String _kind = 'single';
  int? _locationId;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加物品')),
      body: FutureBuilder<List<LocationNode>>(
        future: AppDatabase.instance.getLocations(),
        builder: (context, snapshot) {
          final locations = snapshot.data ?? const <LocationNode>[];
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '物品名称',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入物品名称' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(
                    labelText: '分类',
                    hintText: '例如：医药、清洁、玩具、工具',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: const InputDecoration(
                    labelText: '记录类型',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'single', child: Text('单件物品')),
                    DropdownMenuItem(value: 'quantity', child: Text('数量物品')),
                    DropdownMenuItem(value: 'group', child: Text('箱 / 集合')),
                  ],
                  onChanged: (value) => setState(() => _kind = value ?? 'single'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _locationId,
                  decoration: const InputDecoration(
                    labelText: '存放位置',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final location in locations)
                      DropdownMenuItem(
                        value: location.id,
                        child: Text(location.path, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) => setState(() => _locationId = value),
                  validator: (value) => value == null ? '请选择存放位置' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantity,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '数量',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final number = double.tryParse(value ?? '');
                          return number == null || number < 0 ? '数量不正确' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        decoration: const InputDecoration(
                          labelText: '单位',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.addItem(
        name: _name.text,
        category: _category.text,
        kind: _kind,
        locationId: _locationId!,
        quantity: double.parse(_quantity.text),
        unit: _unit.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _quantity.dispose();
    _unit.dispose();
    _notes.dispose();
    super.dispose();
  }
}

class LocationsPage extends StatefulWidget {
  const LocationsPage({super.key});

  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  late Future<List<LocationNode>> _locations;

  @override
  void initState() {
    super.initState();
    _locations = AppDatabase.instance.getLocations();
  }

  void _reload() {
    setState(() => _locations = AppDatabase.instance.getLocations());
  }

  Future<void> _addLocation() async {
    final locations = await AppDatabase.instance.getLocations();
    if (!mounted) return;

    final nameController = TextEditingController();
    int parentId = locations.first.id;
    String type = 'area';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加位置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：客厅、白色高柜、第二层',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: parentId,
                  decoration: const InputDecoration(labelText: '上级位置'),
                  items: [
                    for (final location in locations)
                      DropdownMenuItem(
                        value: location.id,
                        child: Text(location.path, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => parentId = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: const [
                    DropdownMenuItem(value: 'room', child: Text('房间')),
                    DropdownMenuItem(value: 'furniture', child: Text('家具')),
                    DropdownMenuItem(value: 'shelf', child: Text('层 / 抽屉')),
                    DropdownMenuItem(value: 'container', child: Text('收纳箱')),
                    DropdownMenuItem(value: 'area', child: Text('其他区域')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => type = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                await AppDatabase.instance.addLocation(
                  name: nameController.text,
                  parentId: parentId,
                  type: type,
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<LocationNode>>(
        future: _locations,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final locations = snapshot.data ?? const <LocationNode>[];
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: locations.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final location = locations[index];
              return ListTile(
                leading: Icon(_locationIcon(location.type)),
                title: Text(location.name),
                subtitle: Text(location.path),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLocation,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('添加位置'),
      ),
    );
  }

  IconData _locationIcon(String type) {
    return switch (type) {
      'home' => Icons.home_outlined,
      'room' => Icons.meeting_room_outlined,
      'furniture' => Icons.kitchen_outlined,
      'shelf' => Icons.view_agenda_outlined,
      'container' => Icons.inventory_2_outlined,
      _ => Icons.place_outlined,
    };
  }
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
    return _InventoryOverview(locations, counts);
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

        if (usable.isEmpty) {
          return const _EmptyState(
            icon: Icons.fact_check_outlined,
            title: '还不能盘库',
            subtitle: '先添加位置和物品，然后按位置盘点。',
          );
        }

        return ListView.separated(
          itemCount: usable.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final location = usable[index];
            final count = overview.counts[location.id] ?? 0;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.fact_check_outlined)),
              title: Text(location.path),
              subtitle: Text('$count 种物品'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InventoryDetailPage(location: location),
                  ),
                );
                if (mounted) setState(() => _overview = _load());
              },
            );
          },
        );
      },
    );
  }
}

class _InventoryOverview {
  const _InventoryOverview(this.locations, this.counts);
  final List<LocationNode> locations;
  final Map<int, int> counts;
}

class InventoryDetailPage extends StatefulWidget {
  const InventoryDetailPage({super.key, required this.location});

  final LocationNode location;

  @override
  State<InventoryDetailPage> createState() => _InventoryDetailPageState();
}

class _InventoryDetailPageState extends State<InventoryDetailPage> {
  late Future<List<HomeItem>> _items;
  final Map<int, bool> _checks = {};

  @override
  void initState() {
    super.initState();
    _items = AppDatabase.instance.getItemsAtLocation(widget.location.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('盘库')),
      body: FutureBuilder<List<HomeItem>>(
        future: _items,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          for (final item in items) {
            _checks.putIfAbsent(item.id, () => true);
          }

          return Column(
            children: [
              ListTile(
                title: Text(widget.location.path),
                subtitle: const Text('确认每件物品是否还在这个位置。'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return CheckboxListTile(
                      value: _checks[item.id] ?? true,
                      onChanged: (value) {
                        setState(() => _checks[item.id] = value ?? false);
                      },
                      title: Text(item.name),
                      subtitle: Text('${_formatQuantity(item.quantity)} ${item.unit}'),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _submit(items),
                    icon: const Icon(Icons.done_all),
                    label: const Text('完成本次盘库'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit(List<HomeItem> items) async {
    await AppDatabase.instance.createInventorySession(
      locationId: widget.location.id,
      checks: {
        for (final item in items) item.id: _checks[item.id] ?? true,
      },
    );

    if (!mounted) return;
    final missing = items.where((item) => !(_checks[item.id] ?? true)).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('盘库完成：${items.length} 种，缺失 $missing 种')),
    );
    Navigator.of(context).pop();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
