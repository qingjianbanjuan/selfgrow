import 'package:flutter_test/flutter_test.dart';
import 'package:selfgrow/core/foreground_replay.dart';

/// 移植自开源项目 truescreentime 的 ForegroundSessionReplayTest.kt
/// 这些用例全部来自它的 13 个边界测试
void main() {
  final start = DateTime(2026, 11, 14, 10, 0, 0);
  DateTime at(int ms) => start.add(Duration(milliseconds: ms));
  final end = at(1000 * 1000);

  FgEvent resumed(String pkg, int ms, [String? cls]) =>
      FgEvent(pkg, cls ?? '$pkg.Main', FgEventType.resumed, at(ms));

  FgEvent stopped(String pkg, int ms, [String? cls]) =>
      FgEvent(pkg, cls ?? '$pkg.Main', FgEventType.pausedOrStopped, at(ms));

  group('前台会话还原', () {
    test('窗口内的普通会话', () {
      final r = ForegroundReplay.replay(
        [resumed('a', 100), stopped('a', 600)],
        start,
        end,
      );
      expect(r, {'a': 500});
    });

    test('空事件流', () {
      expect(ForegroundReplay.replay([], start, end), isEmpty);
    });

    test('窗口开始前就开始的会话 → 裁剪到窗口起点', () {
      final r = ForegroundReplay.replay(
        [resumed('a', -5000), stopped('a', 300)],
        start,
        end,
      );
      expect(r, {'a': 300});
    });

    test('窗口结束时还在前台 → 算到窗口结束', () {
      final r = ForegroundReplay.replay(
        [resumed('a', 1000 * 1000 - 400)],
        start,
        end,
      );
      expect(r, {'a': 400});
    });

    test('整段都在窗口之前 → 不算', () {
      final r = ForegroundReplay.replay(
        [resumed('a', -5000), stopped('a', -4000)],
        start,
        end,
      );
      expect(r, isEmpty);
    });

    test('同一 Activity 收到 PAUSED 又收到 STOPPED → 不能双算', () {
      final r = ForegroundReplay.replay(
        [
          resumed('a', 100),
          stopped('a', 600), // PAUSED
          stopped('a', 900), // STOPPED，同类名
        ],
        start,
        end,
      );
      expect(r, {'a': 500});
    });

    test('同包多 Activity 重叠 → 只算一次，且不断开', () {
      // B 在 A 还没 pause 时就 resume（App 内跳转），
      // 这个包从 A.resume 一直前台到 B.stop
      final r = ForegroundReplay.replay(
        [
          resumed('a', 100, 'a.First'),
          resumed('a', 300, 'a.Second'),
          stopped('a', 350, 'a.First'),
          stopped('a', 700, 'a.Second'),
        ],
        start,
        end,
      );
      expect(r, {'a': 600});
    });

    test('没有 RESUMED 的孤儿 PAUSED → 忽略', () {
      final r = ForegroundReplay.replay([stopped('a', 200)], start, end);
      expect(r, isEmpty);
    });

    test('多个 App 交替 → 各自独立计时', () {
      final r = ForegroundReplay.replay(
        [
          resumed('a', 100),
          stopped('a', 200),
          resumed('b', 200),
          stopped('b', 500),
          resumed('a', 500),
          stopped('a', 900),
        ],
        start,
        end,
      );
      expect(r, {'a': 500, 'b': 300});
    });

    test('类名为空 → 用包名兜底，仍能配对', () {
      final r = ForegroundReplay.replay(
        [
          FgEvent('a', null, FgEventType.resumed, at(100)),
          FgEvent('a', null, FgEventType.pausedOrStopped, at(400)),
        ],
        start,
        end,
      );
      expect(r, {'a': 300});
    });

    test('范围倒置 → 空', () {
      expect(ForegroundReplay.replay([resumed('a', 100)], end, start), isEmpty);
    });

    test('超长会话 → 封顶为窗口长度', () {
      final r = ForegroundReplay.replay(
        [
          resumed('a', -100000),
          stopped('a', 1000 * 1000 + 100000),
        ],
        start,
        end,
      );
      expect(r['a'], 1000 * 1000);
      expect(r['a']! <= 1000 * 1000, true);
    });

    test('小窗/分屏：两个 App 同时在前台，各算各的', () {
      final r = ForegroundReplay.replay(
        [
          resumed('video', 100, 'video.Player'),
          resumed('chat', 200, 'chat.Room'), // 小窗打开，video 没停
          stopped('video', 900, 'video.Player'), // video 小窗关掉
          stopped('chat', 1000 * 1000 - 200, 'chat.Room'),
        ],
        start,
        end,
      );
      expect(r['video'], 800);
      expect(r['chat'], 1000 * 1000 - 400);
    });
  });
}
