import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/backup_service.dart';

/// 构建时由 `flutter build` 注入（见 pubspec.yaml 的 version 字段）。
const String _appVersion =
    String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '4.0.0');

/// 设置：数据目录说明、一键备份/恢复、关于。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  String? _message;
  Color _messageColor = Colors.green;

  void _say(String msg, [Color color = Colors.green]) {
    setState(() {
      _message = msg;
      _messageColor = color;
    });
  }

  /// 一键备份：优先 U 盘，没有 U 盘就存到桌面。
  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final drives = await BackupService.removableDrives();
      final target =
          drives.isNotEmpty ? '${drives.first}\\' : BackupService.fallbackDir();
      final path = await BackupService.backupTo(target);
      if (!mounted) return;
      _say(drives.isEmpty ? '已备份到电脑：$path' : '已备份到 U 盘：$path');
    } catch (_) {
      if (!mounted) return;
      _say('备份失败，请重试', Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 从备份恢复：优先找 U 盘里的最新备份，找不到再找桌面。
  Future<void> _restore() async {
    setState(() => _busy = true);
    String? latest;
    String location = '';
    try {
      final drives = await BackupService.removableDrives();
      final locations = [
        for (final d in drives) '$d\\',
        BackupService.fallbackDir(),
      ];
      for (final loc in locations) {
        final backups = BackupService.listBackups(loc);
        if (backups.isNotEmpty) {
          latest = backups.first;
          location = loc;
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (latest == null) {
      _say('没有找到备份文件。请先插上备份过的 U 盘，或先执行一次备份。', Colors.red);
      return;
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复备份'),
        content: Text('将使用最新备份覆盖当前全部数据（名单、红花、抽签、听写录音），'
            '完成后应用会自动重启。\n\n备份文件：${latest!.split('\\').last}'
            '${drivesUsed(location)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复并重启'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await BackupService.restoreFrom(latest);
      if (!mounted) return;
      _say('恢复完成，正在重启…');
      await Future.delayed(const Duration(seconds: 1));
      await BackupService.restartApp();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say('恢复失败，备份文件可能已损坏', Colors.red);
    }
  }

  String drivesUsed(String loc) {
    final isUsb =
        loc.length >= 2 && loc[1] == ':' && loc != BackupService.fallbackDir();
    return isUsb ? '\n（来源：U 盘）' : '\n（来源：本电脑）';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dir = AppDb.dataDir;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '⚙️ 设置',
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('数据目录'),
            subtitle: SelectableText(
              dir.isEmpty ? '初始化中…' : dir,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.usb, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '备份 / 恢复',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '备份包含名单、红花、抽签历史和全部听写录音。'
                  '插着 U 盘就备到 U 盘，没插 U 盘就自动存到桌面；'
                  '恢复时优先使用 U 盘里的最新备份。',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _backup,
                      icon: const Icon(Icons.backup, size: 18),
                      label: const Text('一键备份'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('从备份恢复'),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _message!,
                    style: TextStyle(color: _messageColor),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('数据说明'),
            subtitle: Text('所有数据仅保存在本机，不联网、不上传任何服务器。'
                '如果教室一体机装有系统还原软件，请养成每次课后备份的习惯。'),
          ),
        ),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('小学班级管理系统 · 版本 $_appVersion\n'
                '纯本地单机应用 · 不需要安装、不需要联网、不需要账号。'),
          ),
        ),
      ],
    );
  }
}
