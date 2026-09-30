import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models.dart';
import 'qr_scanner_page.dart';

class MoveItemPage extends StatefulWidget {
  const MoveItemPage({
    super.key,
    required this.item,
  });

  final HomeItem item;

  @override
  State<MoveItemPage> createState() => _MoveItemPageState();
}

class _MoveItemPageState extends State<MoveItemPage> {
  int? _destinationId;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('移动物品')),
      body: FutureBuilder<List<LocationNode>>(
        future: AppDatabase.instance.getLocations(),
        builder: (context, snapshot) {
          final locations = snapshot.data ?? const <LocationNode>[];
          final destinations = locations
              .where((location) => location.id != widget.item.locationId)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.item.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text('当前位置：' + widget.item.locationPath),
              const SizedBox(height: 24),
              DropdownButtonFormField<int>(
                initialValue: _destinationId,
                decoration: const InputDecoration(
                  labelText: '移动到',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final location in destinations)
                    DropdownMenuItem(
                      value: location.id,
                      child: Text(location.path, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _destinationId = value),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _destinationId == null || _saving
                    ? null
                    : () => _moveTo(_destinationId!),
                icon: const Icon(Icons.drive_file_move_outlined),
                label: const Text('确认移动'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _scanAndMove,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫描新位置二维码'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _scanAndMove() async {
    final location = await Navigator.of(context).push<LocationNode>(
      MaterialPageRoute(
        builder: (_) => const QrScannerPage(title: '扫描新的存放位置'),
      ),
    );
    if (location == null || !mounted) return;
    if (location.id == widget.item.locationId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('物品已经在这个位置。')),
      );
      return;
    }
    await _moveTo(location.id);
  }

  Future<void> _moveTo(int locationId) async {
    setState(() => _saving = true);
    try {
      await AppDatabase.instance.moveItem(
        itemId: widget.item.id,
        toLocationId: locationId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
