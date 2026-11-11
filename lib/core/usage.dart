import 'package:flutter/foundation.dart';
import 'package:usage_stats/usage_stats.dart';

import 'models.dart';

/// 读取手机使用情况（需要用户在系统设置里授予「使用情况访问权限」）
class UsageService {
  /// 常见系统 / 桌面包，不参与统计
  static const _skip = {
    'com.android.systemui',
    'com.android.settings',
    'com.android.launcher',
    'com.android.launcher3',
    'com.vivo.launcher',
    'com.bbk.launcher2',
    'com.google.android.apps.nexuslauncher',
    'com.android.permissioncontroller',
    'com.example.selfgrow',
    'com.vivo.systemmanager',
    'com.vivo.upslide',
  };

  static bool _lastPermission = false;
  static DateTime? _lastCheck;

  /// 包名 -> 应用名。一次 queryInstalledApps 建好，之后不再逐包查。
  static final Map<String, String> _names = {};
  static bool _namesLoaded = false;

  /// 预取缓存：开关 App 时直接拿，不重新查
  static Future<List<AppUsageBrief>>? _prefetched;
  static DateTime? _prefetchedSince;

  /// 是否已授予权限（结果缓存 30 秒）
  static Future<bool> hasPermission({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < const Duration(seconds: 30)) {
      return _lastPermission;
    }
    try {
      final r = await UsageStats.checkUsagePermission();
      _lastPermission = r ?? false;
    } catch (_) {
      _lastPermission = false;
    }
    _lastCheck = now;
    return _lastPermission;
  }

  /// 跳系统「使用情况访问权限」设置页
  static Future<void> openPermissionSettings() async {
    try {
      await UsageStats.openUsageAccessSettings();
    } catch (_) {}
  }

  /// 一次性把所有已安装应用的名字缓存起来
  static Future<void> _ensureNames() async {
    if (_namesLoaded) return;
    try {
      final apps = await UsageStats.queryInstalledApps(includeSystem: false);
      for (final a in apps) {
        final n = a.appName?.trim();
        if (n != null && n.isNotEmpty) _names[a.packageName] = n;
      }
      _namesLoaded = true;
      debugPrint('[selfgrow] app names cached: ${_names.length}');
    } catch (e) {
      debugPrint('[selfgrow] queryInstalledApps failed: $e');
    }
  }

  /// 查询 [since] 到现在的应用使用情况
  static Future<List<AppUsageBrief>> recent({
    required DateTime since,
    int limit = 8,
    int minSeconds = 60,
  }) async {
    if (!await hasPermission()) return [];
    final now = DateTime.now();
    if (now.difference(since).inMinutes < 1) return [];

    try {
      await _ensureNames();
      final agg = await UsageStats.queryAndAggregateUsageStats(since, now);

      final raw = <(String, int)>[];
      for (final entry in agg.entries) {
        final pkg = entry.key;
        if (_skip.contains(pkg)) continue;
        if (pkg.contains('systemui') || pkg.contains('launcher')) continue;
        final ms = entry.value.totalTimeInForegroundMs ?? 0;
        if (ms < minSeconds * 1000) continue;
        raw.add((pkg, ms));
      }
      raw.sort((a, b) => b.$2.compareTo(a.$2));

      return raw.take(limit).map((e) {
        final (pkg, ms) = e;
        // 用缓存的名字；缓存里没有再逐包查一次
        var name = _names[pkg];
        if (name == null) {
          name = _fallbackName(pkg);
          // 后台补名字，不阻塞返回
          UsageStats.getAppInfo(pkg).then((info) {
            final n = info?.appName?.trim();
            if (n != null && n.isNotEmpty) _names[pkg] = n;
          }).catchError((_) {});
        }
        return AppUsageBrief(pkg, name, Duration(milliseconds: ms),
            kind: classify(pkg, name));
      }).toList();
    } catch (e) {
      debugPrint('[selfgrow] usage query failed: $e');
      return [];
    }
  }

  /// 预取：启动时就先查，弹窗时直接拿结果
  static Future<List<AppUsageBrief>> prefetch({
    required DateTime since,
    int limit = 8,
  }) {
    final running = _prefetched;
    if (running != null &&
        _prefetchedSince != null &&
        _prefetchedSince!.difference(since).inMinutes.abs() < 10) {
      return running;
    }
    _prefetchedSince = since;
    final f = recent(since: since, limit: limit);
    _prefetched = f;
    return f;
  }

  // ---------------- 应用分类 ----------------

  /// 音乐类 —— 你只用网易云，但把常见的都列上，不吃亏
  static const _musicHints = [
    'cloudmusic', // 网易云音乐
    'qqmusic',
    'kugou',
    'kuwo',
    'spotify',
    'ximalaya',
    'netease.cloud',
    '网易云',
    '云音乐',
    '酷狗',
    '酷我',
    '喜马拉雅',
  ];

  /// 判断这个 App 是不是"听歌"（听歌不算刷手机）
  static UsageKind classify(String pkg, String name) {
    final p = pkg.toLowerCase();
    final n = name.toLowerCase();
    if (_musicHints.any((h) => p.contains(h) || n.contains(h))) {
      return UsageKind.background;
    }
    return UsageKind.immersive;
  }
  /// 拿不到应用名时的兜底（从包名推）
  static String _fallbackName(String pkg) {
    final parts = pkg.split('.');
    var last = parts.isEmpty ? pkg : parts.last;
    if (last.length <= 2 && parts.length >= 2) last = parts[parts.length - 2];
    return last;
  }

  /// 把使用记录压成一行给 AI
  static String briefForAi(List<AppUsageBrief> list) {
    if (list.isEmpty) return '（无记录）';
    return list.map((u) => u.label).join('、');
  }

  /// 总时长
  static Duration totalOf(List<AppUsageBrief> list) {
    var ms = 0;
    for (final u in list) {
      ms += u.duration.inMilliseconds;
    }
    return Duration(milliseconds: ms);
  }

  // ---------------- 精确计时（按事件流，不用日聚合）----------------

  /// 用事件流算每个 App 在 [since, now] 内的真实前台时长。
  ///
  /// 为什么不用 queryAndAggregateUsageStats：
  /// Android 的 UsageStats 是按「天」分桶返回的，查 [今天4点, 现在]
  /// 会把 0~4 点的数据一并算进来 —— 于是"凌晨打过的游戏"会跑到今天的评价里。
  /// 事件流带时间戳，可以精确裁剪到窗口内。
  static Future<List<AppUsageBrief>> recentExact({
    required DateTime since,
    int limit = 8,
    int minSeconds = 60,
  }) async {
    if (!await hasPermission()) return [];
    final now = DateTime.now();
    if (now.difference(since).inMinutes < 1) return [];

    try {
      await _ensureNames();
      final events = await UsageStats.queryEvents(since, now);

      final evs = <(DateTime, String, int)>[];
      for (final e in events) {
        final t = e.timeStampDate;
        final p = e.packageName;
        final ty = e.eventTypeValue;
        if (t == null || p == null || ty == null) continue;
        if (_skip.contains(p)) continue;
        if (p.contains('systemui') || p.contains('launcher')) continue;
        evs.add((t, p, ty));
      }
      evs.sort((a, b) => a.$1.compareTo(b.$1));

      final acc = <String, int>{};
      String? cur;
      DateTime? curStart;

      void close(DateTime at) {
        if (cur != null && curStart != null) {
          final end = at.isAfter(now) ? now : at;
          final ms = end.difference(curStart!).inMilliseconds;
          if (ms > 0) acc[cur!] = (acc[cur] ?? 0) + ms;
        }
        cur = null;
        curStart = null;
      }

      for (final (t, pkg, type) in evs) {
        // 1 = ACTIVITY_RESUMED, 23 = ACTIVITY_STOPPED
        if (type == 1) {
          if (cur == pkg) continue;
          close(t);
          cur = pkg;
          curStart = t;
        } else if (type == 2 || type == 23) {
          if (cur == pkg) close(t);
        }
      }
      // 收尾：到 now 还在前台
      if (cur != null && curStart != null) {
        final ms = now.difference(curStart!).inMilliseconds;
        if (ms > 0) acc[cur!] = (acc[cur] ?? 0) + ms;
      }

      final raw = acc.entries
          .where((e) => e.value >= minSeconds * 1000)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return raw.take(limit).map((e) {
        final pkg = e.key;
        var name = _names[pkg] ?? _fallbackName(pkg);
        return AppUsageBrief(pkg, name, Duration(milliseconds: e.value),
            kind: classify(pkg, name));
      }).toList();
    } catch (e) {
      debugPrint('[selfgrow] usage events failed: $e');
      return [];
    }
  }

  /// 窗口内所有 App 的前台总时长（精确，按事件算）
  /// 用来喂给 AI 当"今天屏幕时长"，避免它自己编一个数
  static Future<Duration> totalScreenTime({required DateTime since}) async {
    final list = await recentExact(since: since, limit: 300, minSeconds: 1);
    return totalOf(list);
  }

  // ---------------- 睡眠推断 ----------------

  /// 找出 [since, until] 内最长的一段"手机没动"，
  /// 超过 [minGap] 就认为是在睡觉。
  /// [mustContain] 不为空时，只接受跨越这个时刻的空白段
  /// （用它锁定"昨晚"那一段，避开白天上班 8 小时的长空白）
  static Future<SleepSpan?> detectSleep({
    required DateTime since,
    required DateTime until,
    Duration minGap = const Duration(hours: 3),
    DateTime? mustContain,
  }) async {
    if (!await hasPermission()) return null;
    try {
      final events = await UsageStats.queryEvents(since, until);
      // 只算「人在操作手机」的事件。
      // 夜里手机还会发 STANDBY_BUCKET_CHANGED / CONFIGURATION_CHANGE 之类的
      // 系统事件，如果全算进去，空白永远凑不到 3 小时。
      const userActivityTypes = {
        1, // ACTIVITY_RESUMED
        2, // ACTIVITY_PAUSED
        15, // SCREEN_INTERACTIVE 亮屏
        16, // SCREEN_NON_INTERACTIVE 熄屏
        17, // KEYGUARD_SHOWN 锁屏
        18, // KEYGUARD_HIDDEN 解锁
      };

      final times = <DateTime>[];
      for (final e in events) {
        final t = e.timeStampDate;
        final ty = e.eventTypeValue;
        if (t == null || ty == null) continue;
        if (!userActivityTypes.contains(ty)) continue;
        times.add(t);
      }
      times.sort();
      debugPrint('[selfgrow] detectSleep: ${times.length} 个用户事件');

      // 窗口两端也算节点
      final pts = <DateTime>[since, ...times, until];
      SleepSpan? best;
      for (var i = 1; i < pts.length; i++) {
        final gap = pts[i].difference(pts[i - 1]);
        if (gap < minGap) continue;
        // 必须覆盖指定时刻（比如今天凌晨 4 点），否则不算"昨晚"
        if (mustContain != null) {
          final covers = !pts[i - 1].isAfter(mustContain) &&
              !pts[i].isBefore(mustContain);
          if (!covers) continue;
        }
        if (best == null || gap > best.duration) {
          best = SleepSpan(pts[i - 1], pts[i]);
        }
      }
      return best;
    } catch (e) {
      debugPrint('[selfgrow] detectSleep failed: $e');
      return null;
    }
  }

  /// 按"睡多久 + 几点睡"判定睡眠属性变化
  static SleepVerdict judgeSleep(SleepSpan s) {
    final h = s.hours;
    int d;
    String why;
    if (h >= 7.5) {
      d = 12;
      why = '睡得够';
    } else if (h >= 6.0) {
      d = 5;
      why = '勉强够';
    } else if (h >= 4.5) {
      d = -5;
      why = '睡眠不足';
    } else {
      d = -12;
      why = '严重不足';
    }

    // 入睡太晚（用睡前最后一次用手机的时间近似）
    final hh = s.from.hour;
    if (hh >= 2 && hh < 7) {
      d -= 4;
      why += '，而且 2 点后才睡';
    } else if (hh == 1 && s.from.minute >= 30) {
      d -= 2;
      why += '，睡得偏晚';
    }

    return SleepVerdict(s, d, why);
  }
}

/// 一段睡眠（手机长时间没动的窗口）
class SleepSpan {
  final DateTime from;
  final DateTime to;
  SleepSpan(this.from, this.to);

  Duration get duration => to.difference(from);
  double get hours => duration.inMinutes / 60.0;

  String get clockText {
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${hhmm(from)} → ${hhmm(to)}';
  }

  String get durationText {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    if (h <= 0) return '$m 分钟';
    return m > 0 ? '$h 小时 $m 分' : '$h 小时';
  }
}

/// 睡眠判定结果
class SleepVerdict {
  final SleepSpan span;
  final int delta;
  final String reason;
  SleepVerdict(this.span, this.delta, this.reason);
}