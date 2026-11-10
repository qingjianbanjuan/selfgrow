import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

/// 全部属性（按分组折叠）
class DetailPage extends StatefulWidget {
  final GameStore store;
  final String? focusGroupId;
  const DetailPage({super.key, required this.store, this.focusGroupId});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Set<String> expanded;

  @override
  void initState() {
    super.initState();
    expanded = widget.focusGroupId != null
        ? {widget.focusGroupId!}
        : widget.store.sortedGroups.map((g) => g.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final groups = widget.store.sortedGroups;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: kBg,
            surfaceTintColor: Colors.transparent,
            title: const Text('属性明细', style: TextStyle(fontSize: 16)),
            actions: [
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: '新建属性',
                onPressed: () => _showAddAttr(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: kSurface2,
            foregroundColor: kText,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('新建分组', style: TextStyle(fontSize: 12.5)),
            onPressed: () => _showAddGroup(context),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: groups.map((g) {
              final open = expanded.contains(g.id);
              final list = widget.store.attrsOf(g.id);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        open ? expanded.remove(g.id) : expanded.add(g.id);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Text(g.emoji,
                                style: const TextStyle(fontSize: 15)),
                            const SizedBox(width: 8),
                            Text(g.name,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Text('${list.length} 项',
                                style: const TextStyle(
                                    fontSize: 11, color: kSub)),
                            const Spacer(),
                            Text(
                              '${(widget.store.groupProgress(g.id) * 100).round()}%',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: g.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              open
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 18,
                              color: kSub,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (open)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Column(
                          children: [
                            if (list.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('还没有属性，点右上角 + 新建',
                                      style: TextStyle(
                                          fontSize: 12, color: kSub)),
                                ),
                              ),
                            ...list.map((a) => _AttrRow(store: widget.store, a: a, groupColor: g.color)),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _showAddAttr(BuildContext context) async {
    final nameCtrl = TextEditingController();
    String? groupId = widget.focusGroupId ??
        (widget.store.sortedGroups.isEmpty
            ? null
            : widget.store.sortedGroups.first.id);
    var kind = AttrKind.ability;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          backgroundColor: kSurface,
          title: const Text('新建属性', style: TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '属性名，比如「游泳」'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: groupId,
                  decoration: const InputDecoration(hintText: '所属分组'),
                  dropdownColor: kSurface2,
                  items: widget.store.sortedGroups
                      .map((g) => DropdownMenuItem(
                            value: g.id,
                            child: Text('${g.emoji} ${g.name}',
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) => setD(() => groupId = v),
                ),
                const SizedBox(height: 12),
                // 关键选择：这个是"能力"还是"状态"
                SegmentedButton<AttrKind>(
                  segments: const [
                    ButtonSegment(
                      value: AttrKind.ability,
                      label: Text('能力', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.trending_up, size: 15),
                    ),
                    ButtonSegment(
                      value: AttrKind.state,
                      label: Text('状态', style: TextStyle(fontSize: 12)),
                      icon: Icon(Icons.water_drop_outlined, size: 15),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setD(() => kind = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle:
                        WidgetStateProperty.all(const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  kind == AttrKind.ability
                      ? '能力型：会累积、有等级（如英语、编程）'
                      : '状态型：有当前值 0~100、没有等级（如卫生、心情）',
                  style: const TextStyle(fontSize: 10.5, color: kSub),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final n = nameCtrl.text.trim();
                if (n.isEmpty || groupId == null) return;
                await widget.store.addAttribute(
                  name: n,
                  groupId: groupId!,
                  emoji: '✨',
                  kind: kind,
                  decay: kind == AttrKind.state ? 3 : 0.5,
                );
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }

  Future<void> _showAddGroup(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('新建分组', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '分组名，比如「健康管理」'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final n = ctrl.text.trim();
              if (n.isEmpty) return;
              await widget.store.addGroup(n);
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
}

class _AttrRow extends StatelessWidget {
  final GameStore store;
  final Attribute a;
  final Color groupColor;
  const _AttrRow(
      {required this.store, required this.a, required this.groupColor});

  @override
  Widget build(BuildContext context) {
    final delta = store.todayDelta(a.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(a.emoji, style: const TextStyle(fontSize: 14)),
          ),
          SizedBox(
            width: 52,
            child: Text(a.name,
                style: const TextStyle(fontSize: 12.5),
                overflow: TextOverflow.ellipsis),
          ),
          // 能力型显示 Lv.N；状态型显示当前数值 + 状态词
          Text(
            a.primaryText,
            style: TextStyle(
                fontSize: 11,
                color: groupColor,
                fontWeight: FontWeight.w600),
          ),
          if (a.isState) ...[
            const SizedBox(width: 4),
            Text(a.stateLabel,
                style: const TextStyle(fontSize: 10, color: kSub)),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: a.isState ? (a.value / 100) : a.progress,
                minHeight: 5,
                backgroundColor: kSurface2,
                valueColor: AlwaysStoppedAnimation(groupColor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              delta == 0 ? '' : '${delta > 0 ? '+' : ''}$delta',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: delta > 0 ? kUp : (delta < 0 ? kDown : kSub),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
