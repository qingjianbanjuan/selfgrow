import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/store.dart';
import 'theme.dart';

Future<void> showSettingsSheet(BuildContext context, GameStore store) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SettingsSheet(store: store),
  );
}

class _SettingsSheet extends StatefulWidget {
  final GameStore store;
  const _SettingsSheet({required this.store});

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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
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
              const SizedBox(height: 16),

              const Text('模型',
                  style: TextStyle(fontSize: 12.5, color: kSub)),
              const SizedBox(height: 6),
              TextField(
                controller: _modelCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(hintText: 'deepseek-chat'),
              ),
              const SizedBox(height: 18),

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

              const SizedBox(height: 22),
              const Divider(color: kSurface2),
              const SizedBox(height: 12),

              const Text('数据',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
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
