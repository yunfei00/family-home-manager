import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backup_service.dart';
import '../data/app_database.dart';
import '../family_sync_service.dart';
import '../models.dart';

class FamilySettingsPage extends StatefulWidget {
  const FamilySettingsPage({super.key});

  @override
  State<FamilySettingsPage> createState() => _FamilySettingsPageState();
}

class _FamilySettingsPageState extends State<FamilySettingsPage> {
  final _serverUrl = TextEditingController();
  final _familyId = TextEditingController();
  final _token = TextEditingController();
  final _familyName = TextEditingController(text: '我的家');

  late Future<List<FamilyMember>> _members;
  SyncProfile _profile = const SyncProfile(
    serverUrl: '',
    familyId: '',
    token: '',
    revision: 0,
  );

  bool _busy = false;
  bool _tokenVisible = false;
  bool _dataChanged = false;
  String _syncStatus = '尚未配置家庭服务器';

  @override
  void initState() {
    super.initState();
    _members = AppDatabase.instance.getFamilyMembers();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await FamilySyncService.instance.loadProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _serverUrl.text = profile.serverUrl;
      _familyId.text = profile.familyId;
      _token.text = profile.token;
      _syncStatus = profile.isConfigured
          ? '已配置 · revision ${profile.revision}'
          : '尚未配置家庭服务器';
    });
  }

  void _reloadMembers() {
    setState(() {
      _members = AppDatabase.instance.getFamilyMembers();
    });
  }

  Future<void> _addMember() async {
    final draft = await showDialog<_MemberDraft>(
      context: context,
      builder: (_) => const _MemberDialog(),
    );
    if (draft == null) return;

    await AppDatabase.instance.addFamilyMember(
      name: draft.name,
      role: draft.role,
    );
    if (!mounted) return;
    _dataChanged = true;
    _reloadMembers();
  }

  Future<void> _deleteMember(FamilyMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除家庭成员？'),
        content: Text('将删除“${member.name}”的本地成员记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AppDatabase.instance.deleteFamilyMember(member.id);
    if (!mounted) return;
    _dataChanged = true;
    _reloadMembers();
  }

  Future<void> _exportBackup() async {
    await _runBusy(() async {
      final path = await BackupService.instance.exportBackupFile();
      if (!mounted) return;
      _showMessage(
        path == null ? '已取消导出' : '备份已保存：$path',
      );
    });
  }

  Future<void> _importBackup() async {
    final confirmed = await _confirmDestructive(
      title: '从备份恢复？',
      message: '恢复会用备份中的家庭数据覆盖当前数据。建议先导出一份当前备份。',
      confirmText: '继续恢复',
    );
    if (!confirmed) return;

    await _runBusy(() async {
      final restored = await BackupService.instance.importBackupFile();
      if (!mounted) return;
      if (restored) {
        _dataChanged = true;
        _reloadMembers();
        _showMessage('备份恢复完成');
      }
    });
  }

  Future<void> _saveProfile() async {
    final profile = SyncProfile(
      serverUrl: _serverUrl.text,
      familyId: _familyId.text,
      token: _token.text,
      revision: _profile.familyId.trim() == _familyId.text.trim() &&
              _profile.serverUrl.trim() == _serverUrl.text.trim()
          ? _profile.revision
          : 0,
    );
    await FamilySyncService.instance.saveProfile(profile);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _syncStatus = profile.isConfigured
          ? '连接信息已保存 · revision ${profile.revision}'
          : '连接信息不完整';
    });
  }

  Future<void> _createFamilySpace() async {
    if (_serverUrl.text.trim().isEmpty) {
      _showMessage('请先填写服务器地址');
      return;
    }

    await _runBusy(() async {
      final profile = await FamilySyncService.instance.createFamilySpace(
        serverUrl: _serverUrl.text,
        familyName: _familyName.text,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _serverUrl.text = profile.serverUrl;
        _familyId.text = profile.familyId;
        _token.text = profile.token;
        _syncStatus = '家庭空间已创建 · revision 0';
      });
      _showMessage('家庭空间已创建，请保存好家庭 ID 和密钥');
    });
  }

  Future<void> _testConnection() async {
    if (_serverUrl.text.trim().isEmpty) {
      _showMessage('请填写服务器地址');
      return;
    }
    await _runBusy(() async {
      final ok = await FamilySyncService.instance.testConnection(
        _serverUrl.text,
      );
      if (!mounted) return;
      setState(() {
        _syncStatus = ok ? '服务器连接正常' : '服务器连接失败';
      });
    });
  }

  Future<void> _pushBackup() async {
    await _saveProfile();
    if (!_profile.isConfigured) {
      _showMessage('请先配置服务器地址、家庭 ID 和密钥');
      return;
    }

    await _runBusy(() async {
      try {
        final updated =
            await FamilySyncService.instance.pushBackup(_profile);
        if (!mounted) return;
        setState(() {
          _profile = updated;
          _syncStatus = '上传完成 · revision ${updated.revision}';
        });
        _showMessage('本机家庭数据已上传');
      } on SyncConflictException catch (error) {
        if (!mounted) return;
        setState(() {
          _syncStatus =
              '检测到服务器新版本 revision ${error.currentRevision}';
        });
        _showMessage('服务器有更新。请先下载服务器备份，再决定如何处理本机变更。');
      }
    });
  }

  Future<void> _pullBackup() async {
    await _saveProfile();
    if (!_profile.isConfigured) {
      _showMessage('请先配置服务器地址、家庭 ID 和密钥');
      return;
    }

    final confirmed = await _confirmDestructive(
      title: '下载服务器数据？',
      message: '服务器备份会覆盖本机家庭数据。建议先导出一份本机备份。',
      confirmText: '下载并覆盖',
    );
    if (!confirmed) return;

    await _runBusy(() async {
      final result =
          await FamilySyncService.instance.pullBackup(_profile);
      if (!mounted) return;
      setState(() {
        _profile = result.profile;
        _syncStatus =
            '已同步到 revision ${result.profile.revision}';
      });

      if (result.restored) {
        _dataChanged = true;
        _reloadMembers();
        _showMessage('服务器数据已恢复到本机');
      } else {
        _showMessage('服务器家庭空间还没有备份');
      }
    });
  }

  Future<void> _copyConnection() async {
    if (!_profile.isConfigured) {
      _showMessage('请先保存完整的服务器连接信息');
      return;
    }

    final text = [
      'Family Home Manager',
      'server=${_profile.serverUrl}',
      'family_id=${_profile.familyId}',
      'token=${_profile.token}',
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _showMessage('连接信息已复制，可粘贴到另一台手机');
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _showMessage('操作失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<bool> _confirmDestructive({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<bool> _handleBack() async {
    Navigator.of(context).pop(_dataChanged);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('家庭与备份')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _title('家庭成员'),
            FutureBuilder<List<FamilyMember>>(
              future: _members,
              builder: (context, snapshot) {
                final members = snapshot.data ?? const <FamilyMember>[];
                return Column(
                  children: [
                    if (members.isEmpty)
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.people_outline),
                          title: Text('还没有家庭成员'),
                          subtitle: Text('可以先添加爸爸、妈妈、孩子等家庭成员。'),
                        ),
                      ),
                    for (final member in members)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              member.name.isEmpty ? '?' : member.name[0],
                            ),
                          ),
                          title: Text(member.name),
                          subtitle: Text(
                            member.role == 'owner' ? '管理员' : '家庭成员',
                          ),
                          trailing: IconButton(
                            tooltip: '删除',
                            onPressed:
                                _busy ? null : () => _deleteMember(member),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _addMember,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('添加家庭成员'),
            ),
            const SizedBox(height: 28),
            _title('本机备份'),
            const Text(
              '完整备份包含位置、物品、照片、库存、采购清单、盘库历史和家庭成员。',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _exportBackup,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('导出备份'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _importBackup,
                    icon: const Icon(Icons.restore),
                    label: const Text('恢复备份'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _title('家庭服务器 / 多设备'),
            TextField(
              controller: _serverUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '例如：http://192.168.1.20:8787',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _familyName,
              decoration: const InputDecoration(
                labelText: '家庭名称（创建空间时使用）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _familyId,
              decoration: const InputDecoration(
                labelText: '家庭 ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _token,
              obscureText: !_tokenVisible,
              decoration: InputDecoration(
                labelText: '家庭密钥',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _tokenVisible ? '隐藏' : '显示',
                  onPressed: () {
                    setState(() {
                      _tokenVisible = !_tokenVisible;
                    });
                  },
                  icon: Icon(
                    _tokenVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sync),
                title: Text(_syncStatus),
                subtitle: const Text(
                  '多设备采用整库快照 + revision 冲突保护，不会静默覆盖更新。',
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _testConnection,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('测试服务器'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _saveProfile,
                  icon: const Icon(Icons.link),
                  label: const Text('保存连接'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _createFamilySpace,
                  icon: const Icon(Icons.add_home_outlined),
                  label: const Text('创建家庭空间'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _copyConnection,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('复制连接信息'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pushBackup,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('上传本机'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _pullBackup,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('下载服务器'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '建议：第一台手机创建家庭空间并上传；第二台手机填入同一组服务器地址、家庭 ID、密钥，然后先“下载服务器”。'
              '若服务器部署在公网，请使用 HTTPS；HTTP 仅建议用于可信家庭局域网/VPN。',
            ),
            if (_busy) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  @override
  void dispose() {
    _serverUrl.dispose();
    _familyId.dispose();
    _token.dispose();
    _familyName.dispose();
    super.dispose();
  }
}

class _MemberDraft {
  const _MemberDraft({
    required this.name,
    required this.role,
  });

  final String name;
  final String role;
}

class _MemberDialog extends StatefulWidget {
  const _MemberDialog();

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<_MemberDialog> {
  final _name = TextEditingController();
  String _role = 'member';

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_MemberDraft(name: name, role: _role));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加家庭成员'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '称呼 / 姓名'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: '角色'),
            items: const [
              DropdownMenuItem(value: 'owner', child: Text('管理员')),
              DropdownMenuItem(value: 'member', child: Text('家庭成员')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _role = value;
                });
              }
            },
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
    super.dispose();
  }
}
