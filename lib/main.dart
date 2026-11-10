import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/ai.dart';
import 'core/store.dart';
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
