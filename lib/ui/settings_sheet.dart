import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/usage.dart';
import 'ask_sheet.dart';
import 'theme.dart';

Future<void> showSettingsSheet(BuildContext context, GameStore store) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SettingsSheet(store: store, hostContext: context),
  );
}

class _SettingsSheet extends StatefulWidget {
  final GameStore store;
  final BuildContext hostContext;

  const _SettingsSheet({required this.store, required this.hostContext});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _keyCtrl =
      TextEditingController(text: AiConfig.apiKey);
  late final TextEditingController _modelCtrl =
      TextEditingController(text: AiConfig.model);
  bool _hide = true;
  bool _saved = false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await AiConfig.setKey(_keyCtrl.text);
    await AiConfig.setModel(_modelCtrl.text);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存到本机'), duration: Duration(seconds: 2)),
    );
  }

  /// 手动触发一次追问（测试用，也方便补记以前的事）
  Future<void> _testAsk() async {
    final host = widget.hostContext;
    Navigator.of(context).pop();

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!host.mounted) return;

    final since = DateTime.now().subtract(const Duration(hours: 6));
    final hasPerm = await UsageService.hasPermission();
    final usage =
        hasPerm ? await UsageService.recent(since: since) : <AppUsageBrief>[];
    if (!host.mounted) return;

    await showAskSheet(
      host,
      widget.store,
      since: since,
      usage: usage,
      hasUsagePermission: hasPerm,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('设置',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: kSub),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ---------- AI ----------
              const Text('DeepSeek API Key',
                  style: TextStyle(fontSize: 12.5, color: kSub)),
              const SizedBox(height: 6),
              TextField(
                controller: _keyCtrl,
                obscureText: _hide,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'sk-...',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _hide ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: kSub),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '只保存在本机，不会上传，也不会进代码仓库。\n不填也能用：走离线关键词规则。',
                style: TextStyle(
                    fontSize: 10.5, height: 1.5, color: kSub.withAlpha(180)),
              ),
              const SizedBox(height: 14),

              const Text('模型', style: TextStyle(fontSize: 12.5, color: kSub)),
              const SizedBox(height: 6),
              TextField(
                controller: _modelCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(hintText: 'deepseek-chat'),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _saved ? kUp : kAccent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text(_saved ? '已保存' : '保存'),
                ),
              ),

              // ---------- 权限 ----------
              const SizedBox(height: 22),
              const Divider(color: kSurface2),
              const SizedBox(height: 12),
              const Text('权限',
                  style:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const _UsagePermissionRow(),

              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testAsk,
                  icon: const Icon(Icons.help_outline, size: 16),
                  label:
                      const Text('试一次追问', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kAccent,
                    side: BorderSide(color: kAccent.withAlpha(80)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),

              // ---------- 数据 ----------
              const SizedBox(height: 20),
              const Divider(color: kSurface2),
              const SizedBox(height: 12),
              const Text('数据',
                  style:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.storage_outlined,
                text:
                    '属性 ${widget.store.attrs.length} 个 · 分组 ${widget.store.groups.length} 个 · 记录 ${widget.store.logs.length} 条',
              ),
              const _InfoRow(
                icon: Icons.cloud_off_outlined,
                text: '全部数据只存在本机，没有云端同步',
              ),
              const _InfoRow(
                icon: Icons.shield_outlined,
                text: 'App 只做陈述，不设目标、不督促、不评价',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「使用情况访问权限」状态行
class _UsagePermissionRow extends StatefulWidget {
  const _UsagePermissionRow();

  @override
  State<_UsagePermissionRow> createState() => _UsagePermissionRowState();
}

class _UsagePermissionRowState extends State<_UsagePermissionRow> {
  bool? granted;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final r = await UsageService.hasPermission(force: true);
    if (!mounted) return;
    setState(() {
      granted = r;
      checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await UsageService.openPermissionSettings();
        await Future<void>.delayed(const Duration(seconds: 1));
        await _check();
      },
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: kSurface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              granted == true ? Icons.check_circle : Icons.error_outline,
              size: 16,
              color: granted == true ? kUp : kDown,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    checking
                        ? '检查中…'
                        : (granted == true ? '已允许读取使用情况' : '未允许读取使用情况'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '允许后能知道你用了哪些 App、分别多久，判断更准。数据只在本机处理。',
                    style: TextStyle(
                        fontSize: 10.5,
                        height: 1.4,
                        color: kSub.withAlpha(180)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: kSub),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: kSub),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 11.5, color: kSub, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
