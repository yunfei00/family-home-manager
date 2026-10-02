import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'data/app_database.dart';
import 'family_sync_service.dart';
import 'models.dart';

class AiAssistantAnswer {
  const AiAssistantAnswer({
    required this.answer,
    required this.source,
  });

  final String answer;
  final String source;
}

class AiItemSuggestion {
  const AiItemSuggestion({
    required this.available,
    this.name = '',
    this.category = '',
    this.kind = 'single',
    this.notes = '',
    this.message = '',
    this.source = 'local',
  });

  final bool available;
  final String name;
  final String category;
  final String kind;
  final String notes;
  final String message;
  final String source;
}

class AiProviderStatus {
  const AiProviderStatus({
    required this.connected,
    required this.modelConfigured,
    required this.model,
    required this.visionModel,
  });

  final bool connected;
  final bool modelConfigured;
  final String model;
  final String visionModel;
}

class AiHomeService {
  AiHomeService._();

  static final AiHomeService instance = AiHomeService._();

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

  Future<AiProviderStatus> status() async {
    final profile = await FamilySyncService.instance.loadProfile();
    if (!profile.isConfigured) {
      return const AiProviderStatus(
        connected: false,
        modelConfigured: false,
        model: '',
        visionModel: '',
      );
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              '${_base(profile.serverUrl)}/api/v1/families/'
              '${Uri.encodeComponent(profile.familyId)}/ai/status',
            ),
            headers: {'Authorization': 'Bearer ${profile.token}'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return const AiProviderStatus(
          connected: false,
          modelConfigured: false,
          model: '',
          visionModel: '',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return AiProviderStatus(
        connected: true,
        modelConfigured: body['configured'] == true,
        model: (body['model'] as String?) ?? '',
        visionModel: (body['vision_model'] as String?) ?? '',
      );
    } catch (_) {
      return const AiProviderStatus(
        connected: false,
        modelConfigured: false,
        model: '',
        visionModel: '',
      );
    }
  }

  Future<AiAssistantAnswer> ask(String question) async {
    final clean = question.trim();
    if (clean.isEmpty) {
      return const AiAssistantAnswer(answer: '请先输入问题。', source: 'local');
    }

    final items = await AppDatabase.instance.getItems();
    final profile = await FamilySyncService.instance.loadProfile();

    if (profile.isConfigured) {
      try {
        final response = await http
            .post(
              Uri.parse(
                '${_base(profile.serverUrl)}/api/v1/families/'
                '${Uri.encodeComponent(profile.familyId)}/ai/ask',
              ),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${profile.token}',
              },
              body: jsonEncode({
                'question': clean,
                'items': [
                  for (final item in items) _contextItem(item),
                ],
              }),
            )
            .timeout(const Duration(seconds: 40));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final answer = (body['answer'] as String?)?.trim();
          if (answer != null && answer.isNotEmpty) {
            return AiAssistantAnswer(
              answer: answer,
              source: (body['source'] as String?) ?? 'server',
            );
          }
        }
      } catch (_) {
        // Fall through to the offline/local answer.
      }
    }

    return _askLocal(clean, items);
  }

  Future<AiItemSuggestion> classify({
    required String name,
    String notes = '',
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      return const AiItemSuggestion(
        available: false,
        message: '请先输入物品名称。',
      );
    }

    final profile = await FamilySyncService.instance.loadProfile();
    if (profile.isConfigured) {
      try {
        final response = await http
            .post(
              Uri.parse(
                '${_base(profile.serverUrl)}/api/v1/families/'
                '${Uri.encodeComponent(profile.familyId)}/ai/classify',
              ),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${profile.token}',
              },
              body: jsonEncode({'name': clean, 'notes': notes}),
            )
            .timeout(const Duration(seconds: 25));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final category = _normalizeCategory(
            (body['category'] as String?) ?? '其他',
          );
          return AiItemSuggestion(
            available: true,
            name: clean,
            category: category,
            kind: _normalizeKind((body['kind'] as String?) ?? 'single'),
            notes: notes,
            message: (body['reason'] as String?) ?? '',
            source: (body['source'] as String?) ?? 'server',
          );
        }
      } catch (_) {
        // Fall through to local classification.
      }
    }

    final local = _classifyLocal(clean, notes);
    return AiItemSuggestion(
      available: true,
      name: clean,
      category: local.$1,
      kind: local.$2,
      notes: notes,
      message: '本机规则分类',
      source: 'local',
    );
  }

  Future<AiItemSuggestion> recognizePhoto(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const AiItemSuggestion(
        available: false,
        message: '照片文件不存在。',
      );
    }

    final profile = await FamilySyncService.instance.loadProfile();
    if (!profile.isConfigured) {
      return const AiItemSuggestion(
        available: false,
        message: '先在“家庭与备份”中创建家庭空间并保存服务器连接。',
      );
    }

    try {
      final bytes = await file.readAsBytes();
      final response = await http
          .post(
            Uri.parse(
              '${_base(profile.serverUrl)}/api/v1/families/'
              '${Uri.encodeComponent(profile.familyId)}/ai/vision',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${profile.token}',
            },
            body: jsonEncode({
              'image_base64': base64Encode(bytes),
              'mime_type': _mimeType(path),
            }),
          )
          .timeout(const Duration(seconds: 75));

      if (response.statusCode != 200) {
        return AiItemSuggestion(
          available: false,
          message: '图片识别请求失败：HTTP ${response.statusCode}',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['available'] != true) {
        return AiItemSuggestion(
          available: false,
          message: (body['message'] as String?) ?? '服务器没有可用的多模态模型。',
        );
      }

      return AiItemSuggestion(
        available: true,
        name: (body['name'] as String?)?.trim() ?? '',
        category: _normalizeCategory(
          (body['category'] as String?) ?? '其他',
        ),
        kind: _normalizeKind((body['kind'] as String?) ?? 'single'),
        notes: (body['notes'] as String?)?.trim() ?? '',
        source: (body['source'] as String?) ?? 'llm',
      );
    } catch (error) {
      return AiItemSuggestion(
        available: false,
        message: '图片识别失败：$error',
      );
    }
  }

  Map<String, Object?> _contextItem(HomeItem item) {
    return {
      'name': item.name,
      'category': item.category,
      'location': item.locationPath,
      'quantity': item.quantity,
      'unit': item.unit,
      'minimum_quantity': item.minimumQuantity,
      'expiry_date': item.expiryDate?.toIso8601String(),
      'notes': item.notes,
    };
  }

  AiAssistantAnswer _askLocal(String question, List<HomeItem> items) {
    final q = question.toLowerCase();
    final matches = items.where((item) {
      final name = item.name.toLowerCase();
      return q.contains(name) || name.contains(q);
    }).toList();

    if (matches.isNotEmpty) {
      final answer = matches.take(8).map((item) {
        return '${item.name}：${item.locationPath}，'
            '数量 ${_format(item.quantity)}${item.unit}';
      }).join('；');
      return AiAssistantAnswer(answer: answer, source: 'local');
    }

    if (q.contains('过期') || q.contains('到期')) {
      final expiring = items.where((item) => item.expiryDate != null).toList()
        ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
      if (expiring.isEmpty) {
        return const AiAssistantAnswer(
          answer: '目前没有记录到期日的物品。',
          source: 'local',
        );
      }
      return AiAssistantAnswer(
        answer: expiring.take(10).map((item) {
          final date = item.expiryDate!;
          return '${item.name}（${date.year}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}）';
        }).join('；'),
        source: 'local',
      );
    }

    if (q.contains('采购') || q.contains('要买') || q.contains('库存不足')) {
      final low = items.where((item) {
        final minimum = item.minimumQuantity;
        return minimum != null && item.quantity <= minimum;
      }).toList();
      if (low.isEmpty) {
        return const AiAssistantAnswer(
          answer: '目前没有达到最低库存线的物品。',
          source: 'local',
        );
      }
      return AiAssistantAnswer(
        answer: '建议补货：${low.map((item) => item.name).join('、')}',
        source: 'local',
      );
    }

    return const AiAssistantAnswer(
      answer: '我暂时没有从现有记录中找到直接答案。可以试试“体温计在哪里”“哪些东西快过期”“哪些需要采购”。',
      source: 'local',
    );
  }

  (String, String) _classifyLocal(String name, String notes) {
    final text = '$name $notes';
    const rules = <String, List<String>>{
      '医药': ['药', '体温', '口罩', '创可贴', '消毒', '退热'],
      '清洁': ['洗衣', '洗洁', '清洁', '拖把', '扫把', '垃圾袋', '洁厕'],
      '玩具': ['玩具', '积木', '汽车', '恐龙', '拼图', '球', '娃娃'],
      '工具': ['螺丝', '扳手', '钳', '锤', '电钻', '卷尺'],
      '食品': ['米', '面', '油', '盐', '牛奶', '零食', '饮料'],
      '衣物': ['衣', '裤', '袜', '鞋', '帽', '外套'],
      '证件': ['身份证', '护照', '户口', '证书', '合同'],
      '电子': ['手机', '电脑', '充电', '耳机', '路由器', '硬盘'],
      '日用品': ['牙膏', '牙刷', '纸巾', '毛巾', '雨伞', '洗发', '沐浴'],
    };
    for (final entry in rules.entries) {
      if (entry.value.any(text.contains)) {
        final quantity = {'日用品', '医药', '清洁', '食品'}.contains(entry.key);
        return (entry.key, quantity ? 'quantity' : 'single');
      }
    }
    return ('其他', 'single');
  }

  String _normalizeCategory(String value) {
    return _categories.contains(value) ? value : '其他';
  }

  String _normalizeKind(String value) {
    return {'single', 'quantity', 'group'}.contains(value) ? value : 'single';
  }

  String _base(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _format(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
