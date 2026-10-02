import 'package:flutter/material.dart';

import '../ai_home_service.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _question = TextEditingController();
  final List<_Message> _messages = [];
  bool _asking = false;
  late Future<AiProviderStatus> _status;

  @override
  void initState() {
    super.initState();
    _status = AiHomeService.instance.status();
  }

  Future<void> _ask([String? preset]) async {
    if (_asking) return;
    final text = (preset ?? _question.text).trim();
    if (text.isEmpty) return;

    setState(() {
      _asking = true;
      _messages.add(_Message(text: text, isUser: true));
      _question.clear();
    });

    try {
      final answer = await AiHomeService.instance.ask(text);
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Message(
            text: answer.answer,
            isUser: false,
            source: answer.source,
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Message(
            text: '查询失败：$error',
            isUser: false,
            source: 'error',
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _asking = false;
        });
      }
    }
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _status = AiHomeService.instance.status();
    });
    await _status;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 家庭助手'),
        actions: [
          IconButton(
            tooltip: '刷新 AI 状态',
            onPressed: _refreshStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<AiProviderStatus>(
            future: _status,
            builder: (context, snapshot) {
              final status = snapshot.data;
              String title;
              String subtitle;
              IconData icon;

              if (status == null) {
                title = '正在检查 AI 服务…';
                subtitle = '基础找物和库存问答仍可在本机完成';
                icon = Icons.hourglass_top_outlined;
              } else if (!status.connected) {
                title = '使用本机家庭数据助手';
                subtitle = '家庭服务器尚未连接；找物、库存、到期查询可继续使用';
                icon = Icons.phone_android_outlined;
              } else if (!status.modelConfigured) {
                title = '家庭服务器已连接';
                subtitle = '尚未配置大模型，当前使用本地规则回答';
                icon = Icons.cloud_done_outlined;
              } else {
                title = 'AI 模型已连接';
                subtitle = status.model.isEmpty
                    ? '服务器模型可用'
                    : '模型：${status.model}';
                icon = Icons.auto_awesome;
              }

              return Card(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: ListTile(
                  leading: Icon(icon),
                  title: Text(title),
                  subtitle: Text(subtitle),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final question in const [
                    '体温计在哪里？',
                    '哪些东西快过期？',
                    '哪些东西需要采购？',
                    '牙膏还有多少？',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(question),
                        onPressed: _asking ? null : () => _ask(question),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const _EmptyAssistant()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return Align(
                        alignment: message.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(message.text),
                                  if (!message.isUser &&
                                      message.source != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      message.source == 'llm'
                                          ? 'AI 模型'
                                          : message.source == 'local'
                                              ? '本机家庭数据'
                                              : message.source!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_asking) const LinearProgressIndicator(),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _question,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _ask(),
                    decoration: const InputDecoration(
                      hintText: '例如：创可贴放在哪里？',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: '发送',
                  onPressed: _asking ? null : _ask,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }
}

class _Message {
  const _Message({
    required this.text,
    required this.isUser,
    this.source,
  });

  final String text;
  final bool isUser;
  final String? source;
}

class _EmptyAssistant extends StatelessWidget {
  const _EmptyAssistant();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 56),
            const SizedBox(height: 16),
            Text(
              '直接问家里的东西',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              '可以问“东西在哪里”“还有多少”“哪些快过期”“哪些需要采购”。'
              '服务器配置大模型后，还可以理解更自然的问题。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
