import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/app_database.dart';
import '../models.dart';

class LocationDetailPage extends StatefulWidget {
  const LocationDetailPage({
    super.key,
    required this.location,
  });

  final LocationNode location;

  @override
  State<LocationDetailPage> createState() => _LocationDetailPageState();
}

class _LocationDetailPageState extends State<LocationDetailPage> {
  late Future<List<HomeItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = AppDatabase.instance.getItemsAtLocation(widget.location.id);
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;

    return Scaffold(
      appBar: AppBar(title: Text(location.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(location.path, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('位置编号：' + location.code),
          const SizedBox(height: 20),
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    QrImageView(
                      data: location.qrPayload,
                      size: 220,
                    ),
                    const SizedBox(height: 8),
                    const Text('打印后贴在这个位置上'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: location.qrPayload));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('二维码内容已复制')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('复制二维码内容'),
          ),
          const SizedBox(height: 24),
          Text('这里有什么', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<List<HomeItem>>(
            future: _items,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!;
              if (items.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('这个位置还没有记录物品'),
                  ),
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    Card(
                      child: ListTile(
                        title: Text(item.name),
                        subtitle: Text(item.category.isEmpty ? item.kind : item.category),
                        trailing: Text(
                          _formatQuantity(item.quantity) + ' ' + item.unit,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
