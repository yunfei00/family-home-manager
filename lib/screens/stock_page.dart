import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models.dart';

String _formatStockQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  late Future<_StockData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_StockData> _load() async {
    final consumables = await AppDatabase.instance.getConsumableItems();
    final lowStock = await AppDatabase.instance.getLowStockItems();
    final expiring = await AppDatabase.instance.getExpiringItems(withinDays: 30);
    final shopping = await AppDatabase.instance.getShoppingList();
    return _StockData(
      consumables: consumables,
      lowStock: lowStock,
      expiring: expiring,
      shopping: shopping,
    );
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _openSettings(HomeItem item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockSettingsPage(item: item),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _addToShopping(HomeItem item) async {
    final added =
        await AppDatabase.instance.addLowStockItemToShoppingList(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? '已加入采购清单：${item.name}' : '采购清单里已经有：${item.name}',
        ),
      ),
    );
    _reload();
  }

  Future<void> _addManualShopping() async {
    final draft = await showDialog<_ShoppingDraft>(
      context: context,
      builder: (_) => const _ShoppingDialog(),
    );
    if (draft == null) return;

    await AppDatabase.instance.addShoppingListEntry(
      name: draft.name,
      quantity: draft.quantity,
      unit: draft.unit,
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StockData>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final expiredCount = data.expiring
            .where((item) =>
                item.expiryDate != null &&
                item.expiryDate!.isBefore(DateTime.now()))
            .length;
        final pendingShopping =
            data.shopping.where((entry) => !entry.checked).length;

        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _data;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SummaryCard(
                    label: '消耗品',
                    value: data.consumables.length,
                    icon: Icons.inventory_2_outlined,
                  ),
                  _SummaryCard(
                    label: '库存不足',
                    value: data.lowStock.length,
                    icon: Icons.warning_amber_outlined,
                  ),
                  _SummaryCard(
                    label: '已过期',
                    value: expiredCount,
                    icon: Icons.event_busy_outlined,
                  ),
                  _SummaryCard(
                    label: '待采购',
                    value: pendingShopping,
                    icon: Icons.shopping_cart_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionTitle(
                title: '库存不足',
                subtitle: '达到或低于最低库存时会出现在这里',
              ),
              if (data.lowStock.isEmpty)
                const _EmptyCard(text: '目前没有低库存物品')
              else
                for (final item in data.lowStock)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.warning_amber_outlined),
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        '现有 ${_formatStockQuantity(item.quantity)} ${item.unit}'
                        ' · 最低 ${_formatStockQuantity(item.minimumQuantity ?? 0)} ${item.unit}',
                      ),
                      trailing: IconButton(
                        tooltip: '加入采购清单',
                        onPressed: () => _addToShopping(item),
                        icon: const Icon(Icons.add_shopping_cart),
                      ),
                      onTap: () => _openSettings(item),
                    ),
                  ),
              const SizedBox(height: 20),
              _SectionTitle(
                title: '保质期提醒',
                subtitle: '展示已过期和未来 30 天内到期的物品',
              ),
              if (data.expiring.isEmpty)
                const _EmptyCard(text: '未来 30 天没有到期物品')
              else
                for (final item in data.expiring)
                  _ExpiryCard(
                    item: item,
                    onTap: () => _openSettings(item),
                  ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _SectionTitle(
                      title: '采购清单',
                      subtitle: '补货建议和临时采购都放这里',
                    ),
                  ),
                  IconButton(
                    tooltip: '手动添加',
                    onPressed: _addManualShopping,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (data.shopping.isEmpty)
                const _EmptyCard(text: '采购清单为空')
              else
                for (final entry in data.shopping)
                  Dismissible(
                    key: ValueKey('shopping-${entry.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) async {
                      await AppDatabase.instance
                          .deleteShoppingListEntry(entry.id);
                      if (mounted) _reload();
                    },
                    child: CheckboxListTile(
                      value: entry.checked,
                      onChanged: (value) async {
                        await AppDatabase.instance.setShoppingListChecked(
                          entry.id,
                          value ?? false,
                        );
                        if (mounted) _reload();
                      },
                      title: Text(
                        entry.name,
                        style: TextStyle(
                          decoration: entry.checked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      subtitle: Text(
                        '${_formatStockQuantity(entry.quantity)} ${entry.unit}',
                      ),
                      secondary: const Icon(Icons.shopping_cart_outlined),
                    ),
                  ),
              const SizedBox(height: 20),
              _SectionTitle(
                title: '消耗品库存',
                subtitle: '点开物品可修改数量、最低库存和保质期',
              ),
              if (data.consumables.isEmpty)
                const _EmptyCard(
                  text: '还没有设置消耗品。可从“物品详情 → 库存设置”开始。',
                )
              else
                for (final item in data.consumables)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.inventory_2_outlined),
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        '${_formatStockQuantity(item.quantity)} ${item.unit}'
                        '${item.minimumQuantity == null ? '' : ' · 最低 ${_formatStockQuantity(item.minimumQuantity!)} ${item.unit}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openSettings(item),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class StockSettingsPage extends StatefulWidget {
  const StockSettingsPage({
    super.key,
    required this.item,
  });

  final HomeItem item;

  @override
  State<StockSettingsPage> createState() => _StockSettingsPageState();
}

class _StockSettingsPageState extends State<StockSettingsPage> {
  late final TextEditingController _quantity;
  late final TextEditingController _minimum;
  late bool _isConsumable;
  DateTime? _expiryDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(
      text: _formatStockQuantity(widget.item.quantity),
    );
    _minimum = TextEditingController(
      text: widget.item.minimumQuantity == null
          ? ''
          : _formatStockQuantity(widget.item.minimumQuantity!),
    );
    _isConsumable = widget.item.isConsumable;
    _expiryDate = widget.item.expiryDate;
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
    );
    if (selected != null && mounted) {
      setState(() {
        _expiryDate = DateTime(
          selected.year,
          selected.month,
          selected.day,
          23,
          59,
          59,
        );
      });
    }
  }

  Future<void> _save() async {
    final quantity = double.tryParse(_quantity.text.trim());
    final minimum = _minimum.text.trim().isEmpty
        ? null
        : double.tryParse(_minimum.text.trim());

    if (quantity == null || quantity < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入正确的当前数量')),
      );
      return;
    }
    if (_isConsumable && minimum != null && minimum < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最低库存不能小于 0')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });
    try {
      await AppDatabase.instance.setItemQuantity(
        widget.item.id,
        quantity,
      );
      await AppDatabase.instance.updateStockSettings(
        itemId: widget.item.id,
        isConsumable: _isConsumable,
        minimumQuantity: _isConsumable ? minimum : null,
        expiryDate: _expiryDate,
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('库存设置 · ${widget.item.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('作为消耗品管理'),
            subtitle: const Text('例如纸巾、牙膏、洗衣液、药品等'),
            value: _isConsumable,
            onChanged: (value) {
              setState(() {
                _isConsumable = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantity,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '当前数量（${widget.item.unit}）',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minimum,
            enabled: _isConsumable,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '最低库存（${widget.item.unit}）',
              hintText: '例如 2',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('保质期 / 到期日'),
              subtitle: Text(
                _expiryDate == null
                    ? '未设置'
                    : _formatDate(_expiryDate!),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_expiryDate != null)
                    IconButton(
                      tooltip: '清除日期',
                      onPressed: () {
                        setState(() {
                          _expiryDate = null;
                        });
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  IconButton(
                    tooltip: '选择日期',
                    onPressed: _pickExpiryDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                  ),
                ],
              ),
              onTap: _pickExpiryDate,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '达到最低库存后会进入“库存不足”；到期前 30 天会进入“保质期提醒”。',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? '保存中…' : '保存库存设置'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    return '${value.year}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _quantity.dispose();
    _minimum.dispose();
    super.dispose();
  }
}

class _StockData {
  const _StockData({
    required this.consumables,
    required this.lowStock,
    required this.expiring,
    required this.shopping,
  });

  final List<HomeItem> consumables;
  final List<HomeItem> lowStock;
  final List<HomeItem> expiring;
  final List<ShoppingListEntry> shopping;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 6),
              Text(
                '$value',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ExpiryCard extends StatelessWidget {
  const _ExpiryCard({
    required this.item,
    required this.onTap,
  });

  final HomeItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final expiry = item.expiryDate!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
    final days = expiryDay.difference(today).inDays;
    final status = days < 0
        ? '已过期 ${-days} 天'
        : days == 0
            ? '今天到期'
            : '$days 天后到期';

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            days < 0 ? Icons.event_busy_outlined : Icons.event_outlined,
          ),
        ),
        title: Text(item.name),
        subtitle: Text(
          '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-'
          '${expiry.day.toString().padLeft(2, '0')} · $status',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: Text(text),
      ),
    );
  }
}

class _ShoppingDraft {
  const _ShoppingDraft({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String name;
  final double quantity;
  final String unit;
}

class _ShoppingDialog extends StatefulWidget {
  const _ShoppingDialog();

  @override
  State<_ShoppingDialog> createState() => _ShoppingDialogState();
}

class _ShoppingDialogState extends State<_ShoppingDialog> {
  final _name = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unit = TextEditingController(text: '个');

  void _submit() {
    final name = _name.text.trim();
    final quantity = double.tryParse(_quantity.text.trim());
    if (name.isEmpty || quantity == null || quantity <= 0) return;

    Navigator.of(context).pop(
      _ShoppingDraft(
        name: name,
        quantity: quantity,
        unit: _unit.text.trim().isEmpty ? '个' : _unit.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加采购项'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称'),
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
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }
}
