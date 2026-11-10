import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/usage.dart';
import '../core/weather.dart';
import 'ask_sheet.dart';
import 'avatar.dart';
import 'detail_page.dart';
import 'record_sheet.dart';
import 'settings_sheet.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  final GameStore store;
  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _askedThisLaunch = false;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  /// 天气是异步的，加载完必须 setState 才会显示
  Future<void> _loadWeather() async {
    await WeatherService.load();
    if (mounted) setState(() {});
  }

  /// 打开 App 时：距上一条记录 >= 30 分钟才问
  Future<void> _maybeAsk() async {
    if (_askedThisLaunch) return;
    _askedThisLaunch = true;
    final store = widget.store;
    if (!store.loaded) return;
    // 从来没记录过，就不打扰
    if (store.lastLoggedAt == null) return;
    if (!store.shouldAsk) return;

    // 距上一条记录超过 12 小时，就按 12 小时算（避免"3 天前"这种怪话）
    var since = store.lastLoggedAt!;
    final maxGap = DateTime.now().subtract(const Duration(hours: 12));
    if (since.isBefore(maxGap)) since = maxGap;

    final hasPerm = await UsageService.hasPermission();
    final usage =
        hasPerm ? await UsageService.recent(since: since) : <AppUsageBrief>[];
    if (!mounted) return;

    final text = await showAskSheet(
      context,
      store,
      since: since,
      usage: usage,
      hasUsagePermission: hasPerm,
    );
    if (!mounted || text == null || text.trim().isEmpty) return;

    await store.markAsked();
    if (!mounted) return;
    // 直接走 AI 判定 + 预览确认
    showRecordSheet(context, store, initialText: text, autoJudge: true);
  }

  /// 状态：心情 / 睡眠 / 体力 的平均
  static double _vitality(GameStore s) {
    double v(String id) {
      final a = s.attr(id);
      if (a == null) return 0.6;
      return a.isState ? a.value / 100 : a.normalized;
    }

    return (v('mood') + v('sleep') + v('stamina')) / 3;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;
        if (!store.loaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final avg = store.overallAvgLevel;
        final w = WeatherService.cached;

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: w != null ? [w.tint, kBg] : [kSurface, kBg],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _Header(store: store, avg: avg, weather: w),
                  _GroupGrid(store: store),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, cons) {
                        final s = (cons.maxWidth * 0.82)
                            .clamp(160.0, cons.maxHeight * 0.95)
                            .toDouble();
                        return Center(
                          child: AvatarFigure(
                            level: avg,
                            vitality: _vitality(store),
                            width: s,
                            height: s * 1.2,
                          ),
                        );
                      },
                    ),
                  ),
                  _Footer(store: store),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 顶部

class _Header extends StatelessWidget {
  final GameStore store;
  final double avg;
  final WeatherInfo? weather;

  const _Header({required this.store, required this.avg, this.weather});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '综合 Lv.${avg.floor()}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (weather != null)
                GestureDetector(
                  onTap: () async {
                    await WeatherService.load(force: true);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kSurface2.withAlpha(160),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      weather!.short,
                      style: const TextStyle(fontSize: 11, color: kText),
                    ),
                  ),
                ),
              IconButton(
                icon:
                    const Icon(Icons.settings_outlined, size: 20, color: kSub),
                onPressed: () => showSettingsSheet(context, store),
                tooltip: '设置',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text(
            store.hasState
                ? '状态 ${store.stateAverage.round()}% · ${store.todayCount} 件事'
                : '${store.todayCount} 件事',
            style: const TextStyle(fontSize: 11, color: kSub),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: store.abilityProgress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: kSurface2,
              valueColor: const AlwaysStoppedAnimation(kAccent),
            ),
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
    final p = store.groupProgress(g.id);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailPage(store: store, focusGroupId: g.id),
      )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: kSurface.withAlpha(200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(g.emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(g.name, style: const TextStyle(fontSize: 11.5, color: kText)),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: kSurface2,
                  valueColor: AlwaysStoppedAnimation(g.color),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(p * 100).round()}%',
              style: const TextStyle(fontSize: 10.5, color: kSub),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          Text(
            today == 0 ? '今天还没有记录' : '今天 $today 件事',
            style: const TextStyle(fontSize: 12, color: kSub),
          ),
          const SizedBox(height: 9),
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
                child: FilledButton.icon(
                  onPressed: () => showDailyComment(context, store),
                  icon: const Icon(Icons.insights_outlined, size: 18),
                  label: const Text('今天怎么样'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2A3A),
                    foregroundColor: kAccent,
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
  await showModalBottomSheet(
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
    // 打开就刷新。放到下一帧，避免在 initState 里同步 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    if (!mounted) return;
    if (!AiConfig.hasKey) {
      setState(() => error = '还没填 DeepSeek Key，去设置里填一下');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });

    final since = GameStore.dayStart();
    final hasPerm = await UsageService.hasPermission();
    final usage = hasPerm
        ? await UsageService.recent(since: since, limit: 8)
        : <AppUsageBrief>[];

    final c = await AiService.dailyComment(
      todayLogs: widget.store.logsToday,
      attrs: widget.store.attrs,
      groups: widget.store.groups,
      weather: WeatherService.cached?.forAi,
      usage: usage,
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
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    // 监听 store：记录一变化，面板立即跟着重建
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final s = widget.store;
    final w = WeatherService.cached;
    final hasContent = (s.commentBody ?? '').isNotEmpty;

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
              if (w != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(w.short,
                      style: const TextStyle(fontSize: 11, color: kSub)),
                ),
              const Spacer(),
              // 刷新按钮常驻，不再藏在"过期才出现"的条件里
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: kSub),
                onPressed: loading ? null : _generate,
                tooltip: '重新生成',
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: kSub),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          // 状态行：生成于 x / 更新中 / 还没有内容
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                if (loading)
                  const Row(
                    children: [
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      ),
                      SizedBox(width: 6),
                      Text('更新中…',
                          style: TextStyle(fontSize: 10.5, color: kSub)),
                    ],
                  )
                else if (hasContent)
                  Text(
                    '生成于 ${s.commentAgeText}',
                    style: TextStyle(
                        fontSize: 10.5, color: kSub.withAlpha(190)),
                  )
                else
                  const SizedBox.shrink(),
                const Spacer(),
                Text('今天 ${s.todayCount} 件事',
                    style: TextStyle(
                        fontSize: 10.5, color: kSub.withAlpha(160))),
              ],
            ),
          ),

          if (error != null && !hasContent)
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
          else if (!hasContent && loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!hasContent)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('今天还没有记录，先记一件事吧',
                  style: TextStyle(color: kSub, fontSize: 13)),
            )
          else ...[
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('刷新失败：$error',
                    style: const TextStyle(fontSize: 11, color: kDown)),
              ),
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
                              style:
                                  const TextStyle(fontSize: 11.5, color: kSub)),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
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
