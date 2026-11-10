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
}
