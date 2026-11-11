import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

/// 记录列表：看今天记了什么、撤销记错的、导出/导入备份
class RecordsPage extends StatelessWidget {
  final GameStore store;
  const RecordsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final logs = store.logs.toList()
          ..sort((a, b) => b.time.compareTo(a.time));

        // 按日期分组
        final groups = <String, List<LogEntry>>{};
        for (final l in logs) {
          groups.putIfAbsent(_dayLabel(l.time), () => []).add(l);
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: kBg,
            surfaceTintColor: Colors.transparent,
            title: Text('记录（${logs.length}）',
                style: const TextStyle(fontSize: 16)),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all_outlined, size: 20),
                tooltip: '导出备份',
                onPressed: () => _export(context),
              ),
              IconButton(
                icon: const Icon(Icons.restore, size: 20),
                tooltip: '从剪贴板恢复',
                onPressed: () => _import(context),
              ),
            ],
          ),
          body: logs.isEmpty
              ? const Center(
                  child: Text('还没有任何记录',
                      style: TextStyle(fontSize: 13, color: kSub)),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    ...groups.entries.expand((e) => [
                          Padding(
                            padding: const EdgeInsets.only(top: 14, bottom: 6),
                            child: Text(e.key,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: kSub,
                                    fontWeight: FontWeight.w600)),
                          ),
                          ...e.value
                              .map((l) => _LogRow(store: store, entry: l)),
                        ]),
                  ],
                ),
        );
      },
    );
  }

  static String _dayLabel(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    final now = DateTime.now();
    final td = DateTime(now.year, now.month, now.day);
    final diff = td.difference(d).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '$diff 天前';
    return '${t.month} 月 ${t.day} 日';
  }

  Future<void> _export(BuildContext context) async {
    final snap = store.exportSnapshot();
    await Clipboard.setData(ClipboardData(text: snap));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text(
        '备份已复制（${snap.length} 字符）\n建议粘贴到备忘录 / 发给自己，重装后再粘回来',
        style: const TextStyle(fontSize: 12.5),
      ),
    ));
  }

  Future<void> _import(BuildContext context) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('剪贴板里没有内容，先请复制备份文本'),
        duration: Duration(seconds: 3),
      ));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('恢复备份', style: TextStyle(fontSize: 15)),
        content: const Text(
          '会用剪贴板里的备份覆盖当前全部数据'
          '（属性、记录都会替换）。\n\n确定吗？',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('覆盖恢复')),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;

    final r = await store.importSnapshot(text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Text(
        r ? '恢复成功：${store.logs.length} 条记录、${store.attrs.length} 个属性'
          : '恢复失败：备份格式不对',
        style: const TextStyle(fontSize: 13),
      ),
    ));
  }
}

class _LogRow extends StatelessWidget {
  final GameStore store;
  final LogEntry entry;
  const _LogRow({required this.store, required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = entry.time;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text('$hh:$mm',
                style: const TextStyle(fontSize: 11.5, color: kSub)),
          ),
          Text(entry.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label,
                    style: const TextStyle(fontSize: 13)),
                if (entry.effects.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: entry.effects.map((e) {
                      final a = store.attr(e.attrId);
                      final name = a?.name ?? e.attrId;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (e.delta >= 0 ? kUp : kDown).withAlpha(26),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '$name${e.delta >= 0 ? '+' : ''}${e.delta}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: e.delta >= 0 ? kUp : kDown,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo, size: 17, color: kSub),
            tooltip: '撤销这条',
            visualDensity: VisualDensity.compact,
            onPressed: () => _undo(context),
          ),
        ],
      ),
    );
  }

  Future<void> _undo(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('撤销这条记录？', style: TextStyle(fontSize: 15)),
        content: Text(
          '${entry.emoji} ${entry.label}\n撤销后属性会回滚',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: kDown),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.undo(entry);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text('已撤销：${entry.label}',
          style: const TextStyle(fontSize: 13)),
    ));
  }
}
