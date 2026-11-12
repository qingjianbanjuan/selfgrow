import 'package:flutter/foundation.dart';
import 'package:usage_stats/usage_stats.dart';

import 'models.dart';

/// 读取手机使用情况（需要用户在系统设置里授予「使用情况访问权限」）
///
/// 两套口径，各管一摊：
/// - [systemToday] 系统天级值：和「健康使用设备」同源同口径，**对得上账**
/// - [recentExact] 事件流：能按任意窗口切（"上条记录到现在"），但精度靠自己拼
class UsageService {
  /// 桌面 / 系统 UI —— 「健康使用设备」不算这部分，我们也不算
  static const _shellPackages = {
    'com.android.systemui',
    'com.android.launcher',
    'com.android.launcher3',
    'com.vivo.launcher',
    'com.bbk.launcher2',
    'com.google.android.apps.nexuslauncher',
    'com.vivo.upslide',
    'com.android.providers',
    'com.android.permissioncontroller',
  };

  /// 是不是"桌面/系统 UI"
  static bool _isShell(String pkg) =>
      _shellPackages.contains(pkg) ||
      pkg.contains('launcher') ||
      pkg.contains('systemui');

  static bool _lastPermission = false;
  static DateTime? _lastCheck;

  /// 包名 -> 应用名。一次 queryInstalledApps 建好。
  static final Map<String, String> _names = {};
  static bool _namesLoaded = false;

  // ---------------- 权限 ----------------

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

  static Future<void> openPermissionSettings() async {
    try {
      await UsageStats.openUsageAccessSettings();
    } catch (_) {}
  }

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

  // ---------------- 分类 ----------------

  /// 音乐类 —— 听歌不算刷手机
  static const _musicHints = [
    'cloudmusic',
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

  static UsageKind classify(String pkg, String name) {
    final p = pkg.toLowerCase();
    final n = name.toLowerCase();
    if (_musicHints.any((h) => p.contains(h) || n.contains(h))) {
      return UsageKind.background;
    }
    return UsageKind.immersive;
  }

  // ---------------- 口径 A：系统天级值 ----------------

  /// 今天（0:00 到现在）的屏幕使用，数据来自系统的 UsageStats。
  ///
  /// 注意：`queryUsageStats` 会把时间**向下取整到 interval 边界**，
  /// 所以只有起点是本地 0:00 时结果才精确 —— 这正是我们要的口径。
  static Future<({List<AppUsageBrief> apps, Duration total})> systemToday({
    DateTime? dayStart,
    int limit = 8,
  }) async {
    if (!await hasPermission()) {
      return (apps: <AppUsageBrief>[], total: Duration.zero);
    }
    final now = DateTime.now();
    final start = dayStart ?? DateTime(now.year, now.month, now.day);

    try {
      await _ensureNames();
      final stats = await UsageStats.queryUsageStats(
        start,
        now,
        intervalType: IntervalType.daily,
      );

      final acc = <String, int>{};
      for (final s in stats) {
        final pkg = s.packageName;
        final ms = s.totalTimeInForegroundMs;
        if (pkg == null || ms == null || ms <= 0) continue;
        // 和「健康使用设备」一致：不算桌面 / 系统 UI
        if (_isShell(pkg)) continue;
        acc[pkg] = (acc[pkg] ?? 0) + ms;
      }

      final totalMs = acc.values.fold<int>(0, (a, b) => a + b);
      final sorted = acc.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final apps = sorted.take(limit).map((e) {
        final name = _names[e.key] ?? _fallbackName(e.key);
        return AppUsageBrief(
          e.key,
          name,
          Duration(milliseconds: e.value),
          kind: classify(e.key, name),
        );
      }).toList();

      debugPrint('[selfgrow] systemToday: ${acc.length} 个包，'
          '总 ${totalMs ~/ 60000} 分钟');
      return (apps: apps, total: Duration(milliseconds: totalMs));
    } catch (e) {
      debugPrint('[selfgrow] systemToday failed: $e');
      return (apps: <AppUsageBrief>[], total: Duration.zero);
    }
  }

  // ---------------- 口径 B：事件流（任意窗口）----------------

  /// 按事件流算 [since, now] 内每个 App 的真实前台时长。
  ///
  /// 关键三点（之前全错）：
  /// 1. **每个包各自开区间**（Map），不是全局一个"当前 App"—— 这样分屏不漏
  /// 2. **RESUMED 不关别人**
  /// 3. **熄屏 / 锁屏时结算所有开着的区间** —— 否则"看视频睡着"会算到天亮
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

      final evs = <(DateTime, String?, int)>[];
      for (final e in events) {
        final t = e.timeStampDate;
        final ty = e.eventTypeValue;
        if (t == null || ty == null) continue;
        evs.add((t, e.packageName, ty));
      }
      evs.sort((a, b) => a.$1.compareTo(b.$1));

      final acc = <String, int>{};
      final open = <String, DateTime>{};

      void settle(String pkg, DateTime at) {
        final st = open.remove(pkg);
        if (st == null) return;
        final s = st.isBefore(since) ? since : st;
        final e = at.isAfter(now) ? now : at;
        if (e.isAfter(s)) {
          acc[pkg] = (acc[pkg] ?? 0) + e.difference(s).inMilliseconds;
        }
      }

      void settleAll(DateTime at) {
        for (final pkg in open.keys.toList()) {
          settle(pkg, at);
        }
      }

      for (final (t, pkg, ty) in evs) {
        switch (ty) {
          case 1: // ACTIVITY_RESUMED
            if (pkg == null || _isShell(pkg)) break;
            open.putIfAbsent(pkg, () => t); // 保留最早的开始
            break;
          case 2: // ACTIVITY_PAUSED
          case 23: // ACTIVITY_STOPPED
            if (pkg != null) settle(pkg, t);
            break;
          case 16: // SCREEN_NON_INTERACTIVE 熄屏
          case 17: // KEYGUARD_SHOWN 锁屏
          case 26: // DEVICE_SHUTDOWN 关机
            settleAll(t);
            break;
        }
      }
      settleAll(now); // 收尾

      final raw = acc.entries
          .where((e) => e.value >= minSeconds * 1000)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return raw.take(limit).map((e) {
        final name = _names[e.key] ?? _fallbackName(e.key);
        return AppUsageBrief(
          e.key,
          name,
          Duration(milliseconds: e.value),
          kind: classify(e.key, name),
        );
      }).toList();
    } catch (e) {
      debugPrint('[selfgrow] usage events failed: $e');
      return [];
    }
  }

  /// 用事件流算总时长（交叉校验用）
  static Future<Duration> totalByEvents({required DateTime since}) async {
    final list = await recentExact(since: since, limit: 400, minSeconds: 1);
    return totalOf(list);
  }

  /// 两个口径对账，打日志。返回差值秒数。
  static Future<int> crossCheck({DateTime? dayStart}) async {
    final start = dayStart ?? _midnight();
    final system = await systemToday(dayStart: start, limit: 400);
    final byEvents = await totalByEvents(since: start);
    final diff = (system.total.inSeconds - byEvents.inSeconds).abs();
    debugPrint('[selfgrow] 对账：系统 ${_fmt(system.total)} / '
        '事件 ${_fmt(byEvents)} / 差 ${diff ~/ 60}分${diff % 60}秒'
        '${diff > 60 ? "  ⚠️ 偏差超过 1 分钟" : "  ✅"}');
    return diff;
  }

  static DateTime _midnight() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _fmt(Duration d) =>
      '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

  // ---------------- 睡眠推断 ----------------

  /// 找 [since, until] 内最长的一段"没人碰手机"，
  /// 且必须跨过 [mustContain]（用来锁定昨晚）。
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
      const userActivityTypes = {1, 2, 15, 16, 17, 18};

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

      final pts = <DateTime>[since, ...times, until];
      SleepSpan? best;
      for (var i = 1; i < pts.length; i++) {
        final gap = pts[i].difference(pts[i - 1]);
        if (gap < minGap) continue;
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

  // ---------------- 工具 ----------------

  static String _fallbackName(String pkg) {
    final parts = pkg.split('.');
    var last = parts.isEmpty ? pkg : parts.last;
    if (last.length <= 2 && parts.length >= 2) last = parts[parts.length - 2];
    return last;
  }

  static String briefForAi(List<AppUsageBrief> list) {
    if (list.isEmpty) return '（无记录）';
    return list.map((u) => u.label).join('、');
  }

  static Duration totalOf(List<AppUsageBrief> list) {
    var ms = 0;
    for (final u in list) {
      ms += u.duration.inMilliseconds;
    }
    return Duration(milliseconds: ms);
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
