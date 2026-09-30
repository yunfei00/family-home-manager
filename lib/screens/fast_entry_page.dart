import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/app_database.dart';
import '../fast_entry_parser.dart';
import '../models.dart';
import 'product_barcode_scanner_page.dart';

class FastEntryPage extends StatefulWidget {
  const FastEntryPage({super.key});

  @override
  State<FastEntryPage> createState() => _FastEntryPageState();
}

class _FastEntryPageState extends State<FastEntryPage> {
  static const _categories = <String>[
    '日用品',
    '医药',
    '清洁',
    '玩具',
    '工具',
    '食品',
    '衣物',
    '证件',
    '电子',
    '其他',
  ];

  final _textController = TextEditingController();
  final _categoryController = TextEditingController(text: '日用品');
  final SpeechToText _speech = SpeechToText();

  late Future<List<LocationNode>> _locationsFuture;
  int? _locationId;
  bool _saving = false;
  bool _listening = false;
  String _voiceBase = '';
  String? _barcode;

  @override
  void initState() {
    super.initState();
    _locationsFuture = AppDatabase.instance.getLocations();
    _textController.addListener(_refreshPreview);
  }

  List<FastEntryDraft> get _drafts =>
      parseFastEntries(_textController.text);

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeech() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) {
        setState(() {
          _listening = false;
        });
      }
      return;
    }

    final available = await _speech.initialize();
    if (!mounted) return;
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前设备没有可用的语音识别服务。')),
      );
      return;
    }

    _voiceBase = _textController.text.trim();
    setState(() {
      _listening = true;
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        final spoken = result.recognizedWords.trim();
        final prefix = _voiceBase.isEmpty ? '' : '$_voiceBase，';
        _textController.text = '$prefix$spoken';
        _textController.selection = TextSelection.collapsed(
          offset: _textController.text.length,
        );
        if (result.finalResult) {
          setState(() {
            _listening = false;
          });
        }
      },
    );
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ProductBarcodeScannerPage(),
      ),
    );
    if (barcode == null || !mounted) return;
    setState(() {
      _barcode = barcode;
    });
  }

  Future<void> _save() async {
    final drafts = _drafts;
    if (_locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择存放位置。')),
      );
      return;
    }
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入要记录的物品。')),
      );
      return;
    }
    if (_barcode != null && drafts.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('商品条码一次只能绑定一个物品。')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      if (_barcode != null) {
        final draft = drafts.single;
        await AppDatabase.instance.addItem(
          name: draft.name,
          category: _categoryController.text,
          kind: draft.quantity == 1 ? 'single' : 'quantity',
          locationId: _locationId!,
          quantity: draft.quantity,
          unit: draft.unit,
          notes: '',
          barcode: _barcode,
        );
      } else {
        await AppDatabase.instance.addItemsBatch(
          items: [
            for (final draft in drafts)
              (
                name: draft.name,
                quantity: draft.quantity,
                unit: draft.unit,
              ),
          ],
          category: _categoryController.text,
          locationId: _locationId!,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已快速录入 ${drafts.length} 种物品')),
      );
      Navigator.of(context).pop(true);
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
    final drafts = _drafts;

    return Scaffold(
      appBar: AppBar(title: const Text('快速录入')),
      body: FutureBuilder<List<LocationNode>>(
        future: _locationsFuture,
        builder: (context, snapshot) {
          final locations = snapshot.data ?? const <LocationNode>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<int>(
                initialValue: _locationId,
                decoration: const InputDecoration(
                  labelText: '统一存放位置',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final location in locations)
                    DropdownMenuItem(
                      value: location.id,
                      child: Text(
                        location.path,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    _locationId = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Text(
                '常用分类',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final category in _categories)
                    ChoiceChip(
                      label: Text(category),
                      selected: _categoryController.text == category,
                      onSelected: (_) {
                        setState(() {
                          _categoryController.text = category;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: '分类名称',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _textController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '批量物品',
                  hintText: '例如：牙膏3支，口罩2盒，体温计1个\n也可以每行写一个',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _saving ? null : _toggleSpeech,
                      icon: Icon(
                        _listening ? Icons.mic : Icons.mic_none_outlined,
                      ),
                      label: Text(_listening ? '停止语音' : '语音录入'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _scanBarcode,
                      icon: const Icon(Icons.barcode_reader),
                      label: const Text('扫商品条码'),
                    ),
                  ),
                ],
              ),
              if (_barcode != null) ...[
                const SizedBox(height: 10),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: const Text('已绑定商品条码'),
                    subtitle: Text(_barcode!),
                    trailing: IconButton(
                      tooltip: '移除条码',
                      onPressed: () {
                        setState(() {
                          _barcode = null;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                '识别预览（${drafts.length} 种）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (drafts.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('输入后会在这里预览'),
                  ),
                )
              else
                for (final draft in drafts)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(draft.name),
                      trailing: Text(
                        '${_formatQuantity(draft.quantity)} ${draft.unit}',
                      ),
                    ),
                  ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.done_all),
                label: Text(_saving ? '保存中…' : '确认批量录入'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  @override
  void dispose() {
    _speech.stop();
    _textController.removeListener(_refreshPreview);
    _textController.dispose();
    _categoryController.dispose();
    super.dispose();
  }
}
