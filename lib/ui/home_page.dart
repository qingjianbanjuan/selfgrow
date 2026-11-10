import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'avatar.dart';
import 'detail_page.dart';
import 'record_sheet.dart';
import 'settings_sheet.dart';
import 'theme.dart';

class HomePage extends StatelessWidget {
  final GameStore store;
  const HomePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final enabled = store.attrs.where((a) => a.enabled).toList();
        final avg = enabled.isEmpty
            ? 1.0
            : enabled.fold<int>(0, (p, a) => p + a.level) / enabled.length;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _Header(store: store, avg: avg),
                _GroupGrid(store: store),
                Expanded(
                  child: Center(
                    child: AvatarFigure(
                      level: avg,
                      vitality: _vitality(store),
                    ),
                  ),
                ),
                _Footer(store: store),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 状态：心情 / 睡眠 / 体力 的平均（按等级归一到 0..1）
  static double _vitality(GameStore s) {
    double norm(String id) {
      final a = s.attr(id);
      if (a == null) return 0.7;
      return ((a.level - 1) / 8).clamp(0.0, 1.0);
    }

    return (norm('mood') + norm('sleep') + norm('stamina')) / 3;
  }
}

// ---------------------------------------------------------------- 顶部

class _Header extends StatelessWidget {
  final GameStore store;
  final double avg;
  const _Header({required this.store, required this.avg});

  @override
  Widget build(BuildContext context) {
    final frac = avg - avg.floorToDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '综合 Lv.${avg.floor()}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${store.totalExp} 经验 · ${store.todayCount} 件事',
                style: const TextStyle(fontSize: 11, color: kSub),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: frac.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: kSurface2,
                valueColor: AlwaysStoppedAnimation(levelColor(avg)),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20, color: kSub),
            onPressed: () => showSettingsSheet(context, store),
            tooltip: '设置',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 属性栏

class _GroupGrid extends StatelessWidget {
  final GameStore store;
  const _GroupGrid({required this.store});

  @override
  Widget build(BuildContext context) {
    final groups = store.sortedGroups;
    final rows = <Widget>[];
    for (var i = 0; i < groups.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            Expanded(child: _GroupTile(store: store, g: groups[i])),
            const SizedBox(width: 8),
            Expanded(
              child: i + 1 < groups.length
                  ? _GroupTile(store: store, g: groups[i + 1])
                  : const SizedBox(),
            ),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}

class _GroupTile extends StatelessWidget {
  final GameStore store;
  final AttrGroup g;
  const _GroupTile({required this.store, required this.g});

  @override
  Widget build(BuildContext context) {
    final lv = store.groupLevel(g.id);
    final count = store.attrsOf(g.id).length;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailPage(store: store, focusGroupId: g.id),
      )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(g.emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(
              g.name,
              style: const TextStyle(fontSize: 11.5, color: kText),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ((lv - 1) / 12).clamp(0.02, 1.0),
                  minHeight: 4,
                  backgroundColor: kSurface2,
                  valueColor: AlwaysStoppedAnimation(g.color),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              lv.toStringAsFixed(1),
              style: const TextStyle(fontSize: 10.5, color: kSub),
            ),
            if (count == 0)
              const Padding(
                padding: EdgeInsets.only(left: 3),
                child: Icon(Icons.add, size: 11, color: kSub),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 底部

class _Footer extends StatelessWidget {
  final GameStore store;
  const _Footer({required this.store});

  @override
  Widget build(BuildContext context) {
    final today = store.todayCount;
    final span = store.todayActiveSpan;
    final spanText = span.inMinutes < 1
        ? ''
        : ' · 跨度 ${span.inHours > 0 ? '${span.inHours}h' : '${span.inMinutes}m'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        children: [
          Text(
            today == 0 ? '今天还没有记录' : '今天 $today 件事$spanText',
            style: const TextStyle(fontSize: 11.5, color: kSub),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showRecordSheet(context, store),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('我做了什么'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showDailyComment(context, store),
                  icon: const Icon(Icons.insights_outlined, size: 18),
                  label: const Text('今天怎么样'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kText,
                    side: const BorderSide(color: kSurface2),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 今日陈述

Future<void> showDailyComment(BuildContext context, GameStore store) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CommentSheet(store: store),
  );
}

class _CommentSheet extends StatefulWidget {
  final GameStore store;
  const _CommentSheet({required this.store});

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.store.commentStale) _generate();
  }

  Future<void> _generate() async {
    if (!AiConfig.hasKey) {
      setState(() => error = '还没填 DeepSeek Key，去设置里填一下');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final c = await AiService.dailyComment(
      todayLogs: widget.store.logsToday,
      attrs: widget.store.attrs,
      groups: widget.store.groups,
    );
    if (!mounted) return;
    if (c == null) {
      setState(() {
        loading = false;
        error = '生成失败（网络或 Key 有问题）';
      });
      return;
    }
    await widget.store.storeComment(
      headline: c.headline,
      body: c.body,
      highlights: c.highlights,
    );
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('今天怎么样',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (!s.commentStale)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18, color: kSub),
                  onPressed: _generate,
                  tooltip: '重新生成',
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: kSub),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  Expanded(
                      child: Text(error!,
                          style: const TextStyle(color: kSub, fontSize: 13))),
                  TextButton(
                    onPressed: () => showSettingsSheet(context, s),
                    child: const Text('去设置'),
                  ),
                ],
              ),
            )
          else if (s.commentBody == null || s.commentBody!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('今天还没有记录，先记一件事吧',
                  style: TextStyle(color: kSub, fontSize: 13)),
            )
          else ...[
            Text(
              s.commentHeadline ?? '',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              s.commentBody!,
              style: const TextStyle(fontSize: 13.5, height: 1.6, color: kText),
            ),
            if (s.commentHighlights.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: s.commentHighlights
                    .map((h) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: kSurface2,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(h,
                              style: const TextStyle(
                                  fontSize: 11.5, color: kSub)),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'AI 只陈述，不评价、不建议',
              style: TextStyle(fontSize: 10.5, color: kSub.withAlpha(140)),
            ),
          ],
        ],
      ),
    );
  }
}
