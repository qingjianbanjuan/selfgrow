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
    'com.android.providers',
    'com.example.selfgrow',
    'com.vivo.systemmanager',
  };

  static bool _lastPermission = false;
  static DateTime? _lastCheck;

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
    } catch (_) {
      // 忽略：部分机型没有这个页
    }
  }

  /// 查询 [since] 到现在的应用使用情况
  static Future<List<AppUsageBrief>> recent({
    required DateTime since,
    int limit = 6,
    int minSeconds = 60,
  }) async {
    if (!await hasPermission()) return [];
    final now = DateTime.now();
    if (now.difference(since).inMinutes < 1) return [];

    try {
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

      final out = <AppUsageBrief>[];
      for (final (pkg, ms) in raw.take(limit)) {
        var name = _fallbackName(pkg);
        try {
          final info = await UsageStats.getAppInfo(pkg);
          final n = info?.appName;
          if (n != null && n.trim().isNotEmpty) name = n.trim();
        } catch (_) {
          // 用兜底名
        }
        out.add(AppUsageBrief(pkg, name, Duration(milliseconds: ms)));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// 拿不到应用名时的兜底（从包名推）
  static String _fallbackName(String pkg) {
    final parts = pkg.split('.');
    var last = parts.isEmpty ? pkg : parts.last;
    if (last.length <= 2 && parts.length >= 2) last = parts[parts.length - 2];
    return last;
  }

  /// 把使用记录压成一行为 AI 的上下文
  static String briefForAi(List<AppUsageBrief> list) {
    if (list.isEmpty) return '（无记录）';
    return list.map((u) => u.label).join('、');
  }
}
