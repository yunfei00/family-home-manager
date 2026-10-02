import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ai_home_service.dart';
import '../data/app_database.dart';
import '../family_sync_service.dart';
import '../models.dart';
import '../photo_store.dart';
import '../reminder_service.dart';
import 'ai_assistant_page.dart';
import 'family_settings_page.dart';
import 'fast_entry_page.dart';
import 'inventory_pro.dart';
import 'item_detail_page.dart';
import 'location_detail_page.dart';
import 'move_item_page.dart';
import 'qr_scanner_page.dart';
import 'reminder_center_page.dart';
import 'stock_page.dart';

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  int _dataRevision = 0;
  bool _syncBusy = false;
  AutoSyncStatus _syncStatus = AutoSyncStatus.notConfigured;
  String _syncMessage = '尚未同步';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runMaintenance();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runMaintenance();
    }
  }

  Future<void> _runMaintenance() async {
    await _runAutoSync();
    await ReminderService.instance.refreshAndNotify();
  }

  Future<void> _runAutoSync({bool force = false}) async {
    if (_syncBusy) return;
    setState(() {
      _syncBusy = true;
    });

    try {
      final result = await FamilySyncService.instance.autoSync(force: force);
      if (!mounted) return;

      setState(() {
        _syncStatus = result.status;
        _syncMessage = result.message;
        if (result.localDataChanged) {
          _dataRevision++;
        }
      });

      if (result.status == AutoSyncStatus.conflict) {
        await ReminderService.instance.showSyncConflict(result.message);
      }
      if (result.localDataChanged) {
        await ReminderService.instance.refreshAndNotify();
      }
      if (!mounted) return;

      if (force ||
          result.status == AutoSyncStatus.conflict ||
          result.status == AutoSyncStatus.downloaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncBusy = false;
        });
      }
    }
  }

  IconData get _syncIcon {
    return switch (_syncStatus) {
      AutoSyncStatus.inSync ||
      AutoSyncStatus.uploaded ||
      AutoSyncStatus.downloaded =>
        Icons.cloud_done_outlined,
      AutoSyncStatus.conflict || AutoSyncStatus.inconsistent =>
        Icons.sync_problem_outlined,
      AutoSyncStatus.offline => Icons.cloud_off_outlined,
      AutoSyncStatus.disabled => Icons.sync_disabled_outlined,
      AutoSyncStatus.notConfigured => Icons.cloud_outlined,
    };
  }

  Future<void> _fastEntry() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FastEntryPage()),
    );
    if (changed == true && mounted) {
      setState(() {
        _dataRevision++;
        _index = 1;
      });
    }
  }

  Future<void> _openReminderCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReminderCenterPage()),
    );
    if (mounted) {
      await ReminderService.instance.refreshAndNotify();
    }
  }

  Future<void> _openAiAssistant() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiAssistantPage()),
    );
  }

  Future<void> _openFamilySettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FamilySettingsPage()),
    );
    if (changed == true && mounted) {
      setState(() {
        _dataRevision++;
      });
    }
    if (mounted) {
      await _runAutoSync();
    }
  }

  Future<void> _scanLocation() async {
    final location = await Navigator.of(context).push<LocationNode>(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (location == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationDetailPage(location: location),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(key: ValueKey('dashboard-$_dataRevision')),
      ItemsPage(key: ValueKey('items-$_dataRevision')),
      LocationsPage(key: ValueKey('locations-$_dataRevision')),
      InventoryPage(key: ValueKey('inventory-$_dataRevision')),
      StockPage(key: ValueKey('stock-$_dataRevision')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭管理'),
        actions: [
          if (_syncBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: _syncMessage,
              onPressed: () => _runAutoSync(force: true),
              icon: Icon(_syncIcon),
            ),
          IconButton(
            tooltip: '提醒中心',
            onPressed: _openReminderCenter,
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(
            tooltip: 'AI 家庭助手',
            onPressed: _openAiAssistant,
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: '家庭与备份',
            onPressed: _openFamilySettings,
            icon: const Icon(Icons.people_outline),
          ),
          IconButton(
            tooltip: '快速录入',
            onPressed: _fastEntry,
            icon: const Icon(Icons.bolt_outlined),
          ),
          IconButton(
            tooltip: '扫描位置二维码',
            onPressed: _scanLocation,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: '物品'),
          NavigationDestination(icon: Icon(Icons.account_tree_outlined), label: '位置'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: '盘库'),
          NavigationDestination(icon: Icon(Icons.shopping_basket_outlined), label: '库存'),
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
        setState(() {
          _summary = AppDatabase.instance.getSummary();
        });
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

  Future<void> _moveItem(HomeItem item) async {
    final moved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MoveItemPage(item: item)),
    );
    if (moved == true) _reload();
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
                    final hasPhoto =
                        PhotoStore.instance.exists(item.photoPath);
                    return ListTile(
                      leading: hasPhoto
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(item.photoPath!),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const CircleAvatar(
                              child: Icon(Icons.inventory_2_outlined),
                            ),
                      title: Text(item.name),
                      subtitle: Text(
                        '${item.locationPath}\n${item.category.isEmpty ? item.kind : item.category}',
                      ),
                      isThreeLine: true,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ItemDetailPage(item: item),
                          ),
                        );
                        if (mounted) _reload();
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${_formatQuantity(item.quantity)} ${item.unit}'),
                          PopupMenuButton<String>(
                            tooltip: '物品操作',
                            onSelected: (value) {
                              if (value == 'move') _moveItem(item);
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'move',
                                child: ListTile(
                                  leading: Icon(Icons.drive_file_move_outlined),
                                  title: Text('移动'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
  bool _pickingPhoto = false;
  bool _aiWorking = false;
  String? _photoPath;

  Future<void> _pickPhoto(ImageSource source) async {
    if (_pickingPhoto) return;
    setState(() {
      _pickingPhoto = true;
    });
    try {
      final path = await PhotoStore.instance.pickAndSave(
        source,
        replacePath: _photoPath,
      );
      if (path == null || !mounted) return;
      setState(() {
        _photoPath = path;
      });
    } finally {
      if (mounted) {
        setState(() {
          _pickingPhoto = false;
        });
      }
    }
  }

  Future<void> _removePhoto() async {
    final oldPath = _photoPath;
    setState(() {
      _photoPath = null;
    });
    await PhotoStore.instance.deletePhoto(oldPath);
  }

  Future<void> _aiClassify() async {
    if (_aiWorking) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先输入物品名称，再进行智能分类。')),
      );
      return;
    }

    setState(() {
      _aiWorking = true;
    });
    try {
      final suggestion = await AiHomeService.instance.classify(
        name: _name.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      if (suggestion.available) {
        setState(() {
          _category.text = suggestion.category;
          _kind = suggestion.kind;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              suggestion.source == 'llm'
                  ? 'AI 已建议分类：${suggestion.category}'
                  : '已按本机规则建议分类：${suggestion.category}',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(suggestion.message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _aiWorking = false;
        });
      }
    }
  }

  Future<void> _aiRecognizePhoto() async {
    final path = _photoPath;
    if (_aiWorking || path == null) return;

    setState(() {
      _aiWorking = true;
    });
    try {
      final suggestion = await AiHomeService.instance.recognizePhoto(path);
      if (!mounted) return;
      if (!suggestion.available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(suggestion.message)),
        );
        return;
      }

      setState(() {
        if (suggestion.name.isNotEmpty) {
          _name.text = suggestion.name;
        }
        if (suggestion.category.isNotEmpty) {
          _category.text = suggestion.category;
        }
        _kind = suggestion.kind;
        if (suggestion.notes.isNotEmpty && _notes.text.trim().isEmpty) {
          _notes.text = suggestion.notes;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 已根据照片补充物品信息。')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _aiWorking = false;
        });
      }
    }
  }

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
                if (_photoPath != null &&
                    PhotoStore.instance.exists(_photoPath))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_photoPath!),
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickingPhoto
                            ? null
                            : () => _pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('拍照'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickingPhoto
                            ? null
                            : () => _pickPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('相册'),
                      ),
                    ),
                  ],
                ),
                if (_photoPath != null) ...[
                  FilledButton.tonalIcon(
                    onPressed: _aiWorking ? null : _aiRecognizePhoto,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(_aiWorking ? 'AI 处理中…' : 'AI 识别照片'),
                  ),
                  TextButton.icon(
                    onPressed:
                        _pickingPhoto || _aiWorking ? null : _removePhoto,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除照片'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(
                    labelText: '分类',
                    hintText: '例如：医药、清洁、玩具、工具',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _aiWorking ? null : _aiClassify,
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('AI 智能分类'),
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
                  onChanged: (value) {
                    setState(() {
                      _kind = value ?? 'single';
                    });
                  },
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
                  onChanged: (value) {
                    setState(() {
                      _locationId = value;
                    });
                  },
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
    setState(() {
      _saving = true;
    });
    try {
      await AppDatabase.instance.addItem(
        name: _name.text,
        category: _category.text,
        kind: _kind,
        locationId: _locationId!,
        quantity: double.parse(_quantity.text),
        unit: _unit.text,
        notes: _notes.text,
        photoPath: _photoPath,
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
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
    setState(() {
      _locations = AppDatabase.instance.getLocations();
    });
  }

  Future<void> _addLocation() async {
    final locations = await AppDatabase.instance.getLocations();
    if (!mounted || locations.isEmpty) return;

    final draft = await showDialog<_LocationDraft>(
      context: context,
      builder: (_) => _AddLocationDialog(locations: locations),
    );
    if (draft == null || !mounted) return;

    try {
      await AppDatabase.instance.addLocation(
        name: draft.name,
        parentId: draft.parentId,
        type: draft.type,
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加位置：${draft.name}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加位置失败：$error')),
      );
    }
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
              final hasPhoto =
                  PhotoStore.instance.exists(location.photoPath);
              return ListTile(
                leading: hasPhoto
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(location.photoPath!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(_locationIcon(location.type)),
                title: Text(location.name),
                subtitle: Text(location.path),
                trailing: const Icon(Icons.qr_code_2),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LocationDetailPage(location: location),
                    ),
                  );
                  if (mounted) _reload();
                },
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


class _LocationDraft {
  const _LocationDraft({
    required this.name,
    required this.parentId,
    required this.type,
  });

  final String name;
  final int parentId;
  final String type;
}

class _AddLocationDialog extends StatefulWidget {
  const _AddLocationDialog({required this.locations});

  final List<LocationNode> locations;

  @override
  State<_AddLocationDialog> createState() => _AddLocationDialogState();
}

class _AddLocationDialogState extends State<_AddLocationDialog> {
  final TextEditingController _nameController = TextEditingController();

  late int _parentId;
  String _type = 'area';

  @override
  void initState() {
    super.initState();
    _parentId = widget.locations.first.id;
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    Navigator.of(context).pop(
      _LocationDraft(
        name: name,
        parentId: _parentId,
        type: _type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加位置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：客厅、白色高柜、第二层',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _parentId,
              decoration: const InputDecoration(labelText: '上级位置'),
              items: [
                for (final location in widget.locations)
                  DropdownMenuItem(
                    value: location.id,
                    child: Text(
                      location.path,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _parentId = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '类型'),
              items: const [
                DropdownMenuItem(value: 'room', child: Text('房间')),
                DropdownMenuItem(value: 'furniture', child: Text('家具')),
                DropdownMenuItem(value: 'shelf', child: Text('层 / 抽屉')),
                DropdownMenuItem(value: 'container', child: Text('收纳箱')),
                DropdownMenuItem(value: 'area', child: Text('其他区域')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _type = value;
                  });
                }
              },
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
          child: const Text('添加'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
