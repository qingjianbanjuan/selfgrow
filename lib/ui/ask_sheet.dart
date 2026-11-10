import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/usage.dart';
import 'theme.dart';

/// 打开 App 时的追问。
/// 返回用户输入的文字（null = 跳过）。
Future<String?> showAskSheet(
  BuildContext context,
  GameStore store, {
  required DateTime since,
  required List<AppUsageBrief> usage,
  required bool hasUsagePermission,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (_) => _AskSheet(
      store: store,
      since: since,
      usage: usage,
      hasUsagePermission: hasUsagePermission,
    ),
  );
}

class _AskSheet extends StatefulWidget {
  final GameStore store;
  final DateTime since;
  final List<AppUsageBrief> usage;
  final bool hasUsagePermission;

  const _AskSheet({
    required this.store,
    required this.since,
    required this.usage,
    required this.hasUsagePermission,
  });

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _sinceText {
    final d = widget.since;
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String get _gapText {
    final gap = DateTime.now().difference(widget.since);
    if (gap.inHours >= 1) {
      return '${gap.inHours} 小时${gap.inMinutes % 60 > 0 ? ' ${gap.inMinutes % 60} 分' : ''}';
    }
    return '${gap.inMinutes} 分钟';
  }

  /// 根据使用记录猜一句
  List<String> get _guesses {
    final g = <String>[];
    final names = widget.usage.map((u) => u.appName).join(' ');
    final pkg = widget.usage.map((u) => u.packageName).join(' ');

    if (names.contains('抖音') || names.contains('快手') || pkg.contains('aweme')) {
      g.add('在刷视频');
    }
    if (names.contains('B站') || names.contains('bilibili') || pkg.contains('bilibili')) {
      g.add('在看视频');
    }
    if (names.contains('微信') || names.contains('QQ') || pkg.contains('tencent.mm')) {
      g.add('在聊天');
    }
    if (names.contains('游戏') || pkg.contains('game')) {
      g.add('在打游戏');
    }
    if (names.contains('知乎') || names.contains('小红书') || pkg.contains('zhihu')) {
      g.add('在看帖子');
    }
    if (widget.usage.isEmpty) {
      return ['在学习', '在外面', '在睡觉', '在吃饭', '在运动'];
    }
    if (!g.contains('在学习')) g.add('在学习');
    if (!g.contains('在外面')) g.add('在外面');
    if (!g.contains('在睡觉')) g.add('在睡觉');
    return g.take(5).toList();
  }

  Future<void> _submit([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_sinceText 之后到现在（$_gapText），你在干什么？',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: kSub),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '记一句就行，AI 会换算成属性变化',
                style: TextStyle(
                    fontSize: 11, color: kSub.withAlpha(190)),
              ),
              const SizedBox(height: 16),

              // ---- 手机使用摘要 ----
              if (widget.hasUsagePermission && widget.usage.isNotEmpty) ...[
                const Text('这段时间的手机使用',
                    style: TextStyle(fontSize: 11.5, color: kSub)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.usage
                      .map((u) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: kSurface2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              u.label,
                              style: const TextStyle(
                                  fontSize: 11.5, color: kText),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
              ] else if (!widget.hasUsagePermission) ...[
                InkWell(
                  onTap: () async {
                    await UsageService.openPermissionSettings();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kSurface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kAccent.withAlpha(60)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.phonelink_setup,
                            size: 16, color: kAccent),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '允许读取「使用情况」，就能知道这段时间你用了哪些 App',
                            style: TextStyle(fontSize: 11.5, color: kSub),
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 16, color: kSub),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ---- 快捷猜测 ----
              const Text('或者快速选一个',
                  style: TextStyle(fontSize: 11.5, color: kSub)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _guesses
                    .map((g) => InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => _submit(g),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 9),
                            decoration: BoxDecoration(
                              color: kSurface2,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(g,
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),

              // ---- 自由输入 ----
              TextField(
                controller: _ctrl,
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '说一句，比如「洗完澡躺床上刷了会儿手机」',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await widget.store.markAsked();
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kSub,
                        side: const BorderSide(color: kSurface2),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('跳过'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccent,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('记下'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
