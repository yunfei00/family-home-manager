import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const MethodChannel _speechChannel =
      MethodChannel('family_home_manager/speech');

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

  late Future<List<LocationNode>> _locationsFuture;
  int? _locationId;
  bool _saving = false;
  bool _speechBusy = false;
  bool? _speechAvailable;
  String _speechMessage = '点击“语音录入”会直接打开手机系统语音识别';
  String? _barcode;

  @override
  void initState() {
    super.initState();
    _locationsFuture = AppDatabase.instance.getLocations();
    _textController.addListener(_refreshPreview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSpeechAvailability();
    });
  }

  List<FastEntryDraft> get _drafts =>
      parseFastEntries(_textController.text);

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _checkSpeechAvailability() async {
    try {
      final available =
          await _speechChannel.invokeMethod<bool>('isAvailable') ?? false;
      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        _speechMessage = available
            ? '系统语音识别可用，点击按钮后直接说出物品'
            : '本机未检测到系统语音识别程序';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _speechMessage =
            '无法检查系统语音识别：${error.message ?? error.code}';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _speechMessage = '当前安装包没有语音桥接，请安装最新版本';
      });
    }
  }

  Future<void> _startSpeech() async {
    if (_speechBusy) return;

    setState(() {
      _speechBusy = true;
      _speechMessage = '正在打开系统语音识别…';
    });

    try {
      final spoken = await _speechChannel
          .invokeMethod<String>('recognizeOnce', <String, Object?>{
        'locale': 'zh-CN',
        'prompt': '请说出要录入的家庭物品，例如：牙膏3支，口罩2盒',
      }).timeout(
        const Duration(seconds: 90),
        onTimeout: () => null,
      );

      if (!mounted) return;
      final text = spoken?.trim() ?? '';
      if (text.isEmpty) {
        setState(() {
          _speechMessage = '没有收到识别结果，可以再点一次重试';
        });
        return;
      }

      final old = _textController.text.trim();
      _textController.text = old.isEmpty ? text : '$old，$text';
      _textController.selection = TextSelection.collapsed(
        offset: _textController.text.length,
      );
      setState(() {
        _speechAvailable = true;
        _speechMessage = '识别完成：$text';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'not_available' => '本机没有可调用的系统语音识别程序',
        'busy' => '语音识别正在使用中，请稍后再试',
        _ => '系统语音输入失败：${error.message ?? error.code}',
      };
      setState(() {
        _speechAvailable = error.code == 'not_available' ? false : _speechAvailable;
        _speechMessage = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _speechMessage = '当前安装包没有语音桥接，请安装最新 APK';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _speechMessage = '系统语音输入失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _speechBusy = false;
        });
      }
    }
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
                      onPressed: _saving || _speechBusy
                          ? null
                          : _startSpeech,
                      icon: Icon(
                        _speechBusy
                            ? Icons.graphic_eq
                            : Icons.mic_none_outlined,
                      ),
                      label: Text(
                        _speechBusy ? '等待系统识别…' : '语音录入',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫商品条码'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(
                    _speechAvailable == false
                        ? Icons.mic_off_outlined
                        : Icons.record_voice_over_outlined,
                  ),
                  title: Text(_speechMessage),
                  subtitle: const Text(
                    '这一版不再等待 speech_to_text 初始化，而是直接调用 Android 系统语音识别界面。',
                  ),
                  trailing: IconButton(
                    tooltip: '重新检测',
                    onPressed: _speechBusy ? null : _checkSpeechAvailability,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
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
    _textController.removeListener(_refreshPreview);
    _textController.dispose();
    _categoryController.dispose();
    super.dispose();
  }
}
