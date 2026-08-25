// M3E Migration 记录：按钮（M3ETextButton/M3EOutlinedButton）已迁移；
// 规则 3 未覆盖组件 TextField/ListView/SnackBar/CircleAvatar 暂用官方 material，
// 待官方 M3E 包覆盖后二次迁移。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:path_provider/path_provider.dart';

import '../data/player_profile.dart';

/// 编辑个人信息页：修改名字、更换头像。
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _nameController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = PlayerProfile.instance.name;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/avatar.png');
    await file.writeAsBytes(bytes, flush: true);
    await PlayerProfile.instance.setAvatarPath(file.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    }
  }

  Future<void> _resetAvatar() async {
    await PlayerProfile.instance.setAvatarPath(null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复默认头像')),
      );
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名字不能为空')),
      );
      return;
    }
    setState(() => _saving = true);
    await PlayerProfile.instance.setName(name);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('名字已更新')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = PlayerProfile.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('编辑个人信息')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 头像区
          M3ECard(
            index: 0,
            position: M3ECardPosition.single,
            outerRadius: 16,
            innerRadius: 4,
            gap: 0,
            padding: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  ListenableBuilder(
                    listenable: profile,
                    builder: (context, _) {
                      return CircleAvatar(
                        radius: 48,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage: profile.avatarPath != null
                            ? FileImage(File(profile.avatarPath!))
                            : null,
                        child: profile.avatarPath == null
                            ? Icon(
                                Icons.person,
                                size: 52,
                                color: theme.colorScheme.onPrimaryContainer,
                              )
                            : null,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: M3EOutlinedButton.icon(
                          onPressed: _pickAvatar,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('从相册选择'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: M3ETextButton(
                          onPressed: _resetAvatar,
                          child: const Text('恢复默认'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 名字区
          M3ECard(
            index: 0,
            position: M3ECardPosition.single,
            outerRadius: 16,
            innerRadius: 4,
            gap: 0,
            padding: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '昵称',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    maxLength: 20,
                    decoration: InputDecoration(
                      hintText: '输入你的昵称',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _saveName(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: M3EFilledButton.icon(
                      onPressed: _saving ? null : _saveName,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
