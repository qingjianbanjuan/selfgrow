import 'package:flutter_test/flutter_test.dart';
import 'package:selfgrow/core/models.dart';
import 'package:selfgrow/core/usage.dart';

void main() {
  group('听歌 vs 刷手机（只分两类）', () {
    test('网易云音乐 = 背景音乐，不算刷手机', () {
      final k = UsageService.classify('com.netease.cloudmusic', '网易云音乐');
      expect(k, UsageKind.background);

      final u = AppUsageBrief(
          'com.netease.cloudmusic', '网易云音乐', const Duration(hours: 1),
          kind: k);
      expect(u.isBackground, true);
      expect(u.countsAsScreenTime, false);
    });

    test('其他音乐 App 也认', () {
      for (final pkg in [
        'com.tencent.qqmusic',
        'com.kugou.android',
        'com.kuwo.player',
        'com.ximalaya.ting.android',
      ]) {
        expect(UsageService.classify(pkg, '某音乐'),
            UsageKind.background,
            reason: pkg);
      }
    });

    test('抖音 / 王者 / B站 / 学习 App 都算刷手机', () {
      expect(UsageService.classify('com.ss.android.ugc.aweme', '抖音'),
          UsageKind.immersive);
      expect(UsageService.classify('com.tencent.tmgp.sgame', '王者荣耀'),
          UsageKind.immersive);
      expect(UsageService.classify('tv.danmaku.bili', '哔哩哔哩'),
          UsageKind.immersive);
      // 学习类不再单独分类：AI 会根据事件性质判断影响，不需要代码区分
      expect(UsageService.classify('com.fenbi.android.yingyu', '粉笔四六级'),
          UsageKind.immersive);
    });

    test('未知应用默认算刷手机', () {
      expect(UsageService.classify('com.some.unknown.app', '某未知App'),
          UsageKind.immersive);
    });
  });

  group('纯听歌场景识别', () {
    test('只有网易云 -> 纯听歌（需要问在干嘛）', () {
      final list = [
        AppUsageBrief('com.netease.cloudmusic', '网易云音乐',
            const Duration(hours: 1),
            kind: UsageKind.background),
      ];
      final screen = list.where((u) => !u.isBackground).toList();
      final music = list.where((u) => u.isBackground).toList();
      expect(screen.isEmpty && music.isNotEmpty, true);
    });

    test('网易云 + 抖音 -> 不是纯听歌（抖音已经说明在干嘛）', () {
      final list = [
        AppUsageBrief('com.netease.cloudmusic', '网易云音乐',
            const Duration(hours: 1),
            kind: UsageKind.background),
        AppUsageBrief('com.ss.android.ugc.aweme', '抖音',
            const Duration(minutes: 30),
            kind: UsageKind.immersive),
      ];
      final screen = list.where((u) => !u.isBackground).toList();
      expect(screen.isEmpty, false);
    });
  });

  group('总时长统计', () {
    test('合计正确', () {
      final list = [
        AppUsageBrief('a', 'A', const Duration(minutes: 30)),
        AppUsageBrief('b', 'B', const Duration(minutes: 45)),
      ];
      expect(UsageService.totalOf(list).inMinutes, 75);
    });
  });
}
