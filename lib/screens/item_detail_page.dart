import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_database.dart';
import '../models.dart';
import '../photo_store.dart';
import 'stock_page.dart';

class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({
    super.key,
    required this.item,
  });

  final HomeItem item;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  late HomeItem _item;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      final path = await PhotoStore.instance.pickAndSave(
        source,
        replacePath: _item.photoPath,
      );
      if (path == null) return;

      await AppDatabase.instance.updateItemPhoto(_item.id, path);
      final updated = await AppDatabase.instance.getItemById(_item.id);
      if (!mounted || updated == null) return;

      setState(() {
        _item = updated;
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
      final oldPath = _item.photoPath;
      await AppDatabase.instance.updateItemPhoto(_item.id, null);
      await PhotoStore.instance.deletePhoto(oldPath);

      final updated = await AppDatabase.instance.getItemById(_item.id);
      if (!mounted || updated == null) return;
      setState(() {
        _item = updated;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openStockSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockSettingsPage(item: _item),
      ),
    );
    if (changed != true || !mounted) return;

    final updated = await AppDatabase.instance.getItemById(_item.id);
    if (!mounted || updated == null) return;
    setState(() {
      _item = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = PhotoStore.instance.exists(_item.photoPath);

    return Scaffold(
      appBar: AppBar(title: Text(_item.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: hasPhoto
                ? Image.file(
                    File(_item.photoPath!),
                    height: 260,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  )
                : const SizedBox(
                    height: 180,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera_outlined, size: 48),
                          SizedBox(height: 8),
                          Text('还没有物品照片'),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _busy ? null : () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('拍照'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _busy ? null : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('相册'),
                ),
              ),
            ],
          ),
          if (hasPhoto)
            TextButton.icon(
              onPressed: _busy ? null : _removePhoto,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除照片'),
            ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('存放位置'),
            subtitle: Text(_item.locationPath),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('分类'),
            subtitle: Text(_item.category.isEmpty ? '未分类' : _item.category),
          ),
          ListTile(
            leading: const Icon(Icons.numbers_outlined),
            title: const Text('数量'),
            subtitle:
                Text('${_formatQuantity(_item.quantity)} ${_item.unit}'),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_basket_outlined),
            title: const Text('库存管理'),
            subtitle: Text(_stockSummary(_item)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openStockSettings,
          ),
          if (_item.barcode != null && _item.barcode!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('商品条码'),
              subtitle: SelectableText(_item.barcode!),
            ),
          if (_item.notes.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('备注'),
              subtitle: Text(_item.notes),
            ),
        ],
      ),
    );
  }

  String _stockSummary(HomeItem item) {
    final parts = <String>[];
    parts.add(item.isConsumable ? '消耗品' : '未启用消耗品管理');
    if (item.minimumQuantity != null) {
      parts.add(
        '最低 ${_formatQuantity(item.minimumQuantity!)} ${item.unit}',
      );
    }
    if (item.expiryDate != null) {
      final value = item.expiryDate!;
      parts.add(
        '到期 ${value.year}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}',
      );
    }
    return parts.join(' · ');
  }

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
