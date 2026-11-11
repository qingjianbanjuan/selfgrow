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

  group('睡眠判定（睡多久 + 几点睡）', () {
    // 入睡小时 >= 12 视为「前一天晚上」，否则视为「当天凌晨」
    SleepSpan span(int sh, int sm, int eh, int em) {
      final fromDay = sh >= 12 ? 10 : 11; // 11-10 晚 或 11-11 凌晨
      final from = DateTime(2026, 11, fromDay, sh, sm);
      final to = DateTime(2026, 11, 11, eh, em);
      return SleepSpan(from, to);
    }

    test('22:00 → 06:00（8 小时）=> +12 睡够了', () {
      final v = UsageService.judgeSleep(span(22, 0, 6, 0));
      expect(v.span.hours, closeTo(8.0, 0.01));
      expect(v.delta, 12);
    });

    test('01:00 → 07:30（6.5 小时）=> +5 勉强够', () {
      expect(UsageService.judgeSleep(span(1, 0, 7, 30)).delta, 5);
    });

    test('01:00 → 06:00（5 小时）=> -5 不足', () {
      expect(UsageService.judgeSleep(span(1, 0, 6, 0)).delta, -5);
    });

    test('03:00 → 06:00（3 小时）=> -12 严重不足，还额外 -4', () {
      final v = UsageService.judgeSleep(span(3, 0, 6, 0));
      expect(v.delta, -16);
      expect(v.reason, contains('2 点后'));
    });

    test('00:30 → 08:30（8 小时）=> +12，不算晚睡', () {
      expect(UsageService.judgeSleep(span(0, 30, 8, 30)).delta, 12);
    });

    test('01:40 入睡算偏晚', () {
      final v = UsageService.judgeSleep(span(1, 40, 8, 40));
      // 7 小时 -> +5，偏晚 -2
      expect(v.delta, 3);
      expect(v.reason, contains('偏晚'));
    });
  });
}