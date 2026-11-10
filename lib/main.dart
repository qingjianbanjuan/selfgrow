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