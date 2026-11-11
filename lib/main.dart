import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/ai.dart';
import 'core/usage.dart';
import 'core/store.dart';
import 'core/weather.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 状态栏透明，跟随深色背景
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await AiConfig.load();

  final store = GameStore();
  await store.load();

  // 天气在后台拉，不阻塞启动
  WeatherService.load();

  // 自检：确认使用统计能读到数据（结果打到 logcat）
  _selfCheckUsage();
  // 打开 App 的第一件事：先查「上次记录到现在」的手机使用记录（预取）。
  // 这样追问弹窗能立刻把使用明细摆出来，不用等查询。
  final askSince = store.askSince;
  if (store.shouldAsk && askSince != null) {
    debugPrint('[selfgrow] 预取使用记录：$askSince -> now');
    UsageService.prefetch(since: askSince);
  }
  _selfCheckAi(store);
  _selfCheckWindow(store);

  runApp(SelfGrowApp(store: store));
}

class SelfGrowApp extends StatelessWidget {
  final GameStore store;
  const SelfGrowApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '养成自己',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomePage(store: store),
    );
  }
}

/// 启动自检：把权限状态和最近 6 小时的使用情况打到 logcat
Future<void> _selfCheckUsage() async {
  try {
    final ok = await UsageService.hasPermission(force: true);
    debugPrint('[selfgrow] usage permission = $ok');
    if (!ok) return;
    final list = await UsageService.recent(
      since: DateTime.now().subtract(const Duration(hours: 6)),
      limit: 8,
    );
    debugPrint('[selfgrow] usage count = ${list.length}');
    for (final u in list) {
      debugPrint('[selfgrow]   ${u.label}  (${u.packageName})');
    }
  } catch (e) {
    debugPrint('[selfgrow] usage check failed: $e');
  }
}
/// 启动自检：确认 AI 这条链路通不通（结果打到 logcat）
Future<void> _selfCheckAi(GameStore store) async {
  debugPrint('[selfgrow] === AI 自检 ===');
  debugPrint('[selfgrow] key filled = ${AiConfig.hasKey}'
      ' (长度 ${AiConfig.apiKey.length})');
  debugPrint('[selfgrow] model = ${AiConfig.model}');
  debugPrint('[selfgrow] key 前6位 = ${AiConfig.apiKey.length >= 6 ? AiConfig.apiKey.substring(0, 6) : "(太短)"}');
  if (!AiConfig.hasKey) {
    debugPrint('[selfgrow] 没填 Key，跳过');
    return;
  }

  final c = await AiService.dailyComment(
    todayLogs: store.logsToday,
    attrs: store.attrs,
    groups: store.groups,
    weather: WeatherService.cached?.forAi,
  );
  if (c == null) {
    debugPrint('[selfgrow] dailyComment = NULL（失败）');
  } else {
    debugPrint('[selfgrow] dailyComment OK');
    debugPrint('[selfgrow]   headline = "${c.headline}"');
    debugPrint('[selfgrow]   body     = "${c.body}"');
    debugPrint('[selfgrow]   highlights = ${c.highlights}');
  }

  // 验证「事件性质 × 时长」是否真的影响判定：
  // 同一件事（打游戏），30 分钟 vs 5 小时，delta 应该差很多
  for (final hours in [0.5, 5.0]) {
    final d = Duration(minutes: (hours * 60).round());
    final j = await AiService.judge(
      text: '打游戏',
      attrs: store.attrs,
      groups: store.groups,
      duration: d,
    );
    if (j == null) {
      debugPrint('[selfgrow] judge(${hours}h) = NULL');
      continue;
    }
    final eff = j.effects.map((e) {
      final name = store.attr(e.attrId)?.name ?? e.attrId;
      return '$name${e.delta >= 0 ? '+' : ''}${e.delta}';
    }).join(' ');
    debugPrint('[selfgrow] judge(打游戏 ${hours}h) -> "${j.summary}"'
        ' [${j.durationText}] : $eff');
  }

  debugPrint('[selfgrow] === 自检结束 ===');
}

/// 自检：验证「今天 4 点截断」和「睡眠推断」
Future<void> _selfCheckWindow(GameStore store) async {
  final dayStart = GameStore.dayStart();
  debugPrint('[selfgrow] === 时间窗口自检 ===');
  debugPrint('[selfgrow] 今天起点 = $dayStart（应该是今天 04:00）');

  final today = await UsageService.recentExact(since: dayStart, limit: 8);
  debugPrint('[selfgrow] 今天(4点后)的使用 ${today.length} 项:');
  for (final u in today) {
    debugPrint('[selfgrow]   ${u.label}');
  }

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final span = await UsageService.detectSleep(
    since: todayStart.subtract(const Duration(hours: 6)),
    until: now,
    mustContain: GameStore.dayStart(),
  );
  if (span == null) {
    debugPrint('[selfgrow] 睡眠: 没检测到（昨晚没有跨 4 点的 >=3 小时空白）');
  } else {
    final v = UsageService.judgeSleep(span);
    debugPrint('[selfgrow] 睡眠: ${span.clockText} 共 ${span.durationText}'
        ' -> 睡眠${v.delta >= 0 ? '+' : ''}${v.delta}（${v.reason}）');
  }
  debugPrint('[selfgrow] === 自检结束 ==='.replaceAll('自检结束', '窗口自检结束'));
}