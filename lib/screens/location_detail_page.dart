import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/app_database.dart';
import '../models.dart';
import '../photo_store.dart';

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
  late LocationNode _location;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _location = widget.location;
    _items = AppDatabase.instance.getItemsAtLocation(widget.location.id);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      final path = await PhotoStore.instance.pickAndSave(
        source,
        replacePath: _location.photoPath,
      );
      if (path == null) return;

      await AppDatabase.instance.updateLocationPhoto(_location.id, path);
      final updated =
          await AppDatabase.instance.getLocationById(_location.id);
      if (!mounted || updated == null) return;

      setState(() {
        _location = updated;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _removePhoto() async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      final oldPath = _location.photoPath;
      await AppDatabase.instance.updateLocationPhoto(_location.id, null);
      await PhotoStore.instance.deletePhoto(oldPath);

      final updated =
          await AppDatabase.instance.getLocationById(_location.id);
      if (!mounted || updated == null) return;
      setState(() {
        _location = updated;
      });
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
    final location = _location;
    final hasPhoto = PhotoStore.instance.exists(location.photoPath);

    return Scaffold(
      appBar: AppBar(title: Text(location.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(location.path, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('位置编号：${location.code}'),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: hasPhoto
                ? Image.file(
                    File(location.photoPath!),
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  )
                : const SizedBox(
                    height: 150,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera_outlined, size: 42),
                          SizedBox(height: 8),
                          Text('拍一张位置照片，找东西会更直观'),
                        ],
                      ),
                    ),
                  ),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _busy ? null : () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('拍位置'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _busy ? null : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从相册选'),
                ),
              ),
            ],
          ),
          if (hasPhoto)
            TextButton.icon(
              onPressed: _busy ? null : _removePhoto,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除位置照片'),
            ),
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
              await Clipboard.setData(
                ClipboardData(text: location.qrPayload),
              );
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
                        leading: PhotoStore.instance.exists(item.photoPath)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(item.photoPath!),
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : null,
                        title: Text(item.name),
                        subtitle: Text(
                          item.category.isEmpty ? item.kind : item.category,
                        ),
                        trailing: Text(
                          '${_formatQuantity(item.quantity)} ${item.unit}',
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
