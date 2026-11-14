/// 从 UsageEvents 事件流还原"每个 App 在前台待了多久"。
///
/// 这不是我自己想的算法 —— 是照着开源项目 `DaanyaalSobani/truescreentime`
/// 的 `ForegroundSessionReplay.kt` 移植的（MIT），它带 13 个边界测试：
///   - 窗口开始前就在前台的会话（lookback 后裁剪）
///   - 同一个包多个 Activity 重叠（A 停 B 还在 → 不能断开）
///   - 同一个 Activity 收到 PAUSED 又收到 STOPPED（要幂等，不能双算）
///   - 没有对应 RESUMED 的孤儿 PAUSED（忽略）
///   - 多个 App 交替（各自独立计时）
///   - 类名为空（退化用包名配对）
///   - 长会话（裁剪到窗口长度）
library;

/// 只保留还原前台会话必需的信息
class FgEvent {
  final String pkg;
  final String? cls;
  final FgEventType type;
  final DateTime at;

  const FgEvent(this.pkg, this.cls, this.type, this.at);
}

enum FgEventType { resumed, pausedOrStopped }

class ForegroundReplay {
  ForegroundReplay._();

  /// 返回 包名 -> 前台毫秒数。
  ///
  /// [events] 可以包含 [rangeStart] 之前的事件（lookback），
  /// 用来还原"窗口开始时就已经在前台"的会话；累加时会裁剪到窗口内。
  static Map<String, int> replay(
    List<FgEvent> events,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    if (!rangeEnd.isAfter(rangeStart)) return {};

    final totals = <String, int>{};

    // 每个包：当前处于 resumed 状态的 Activity 类名集合
    final resumedClasses = <String, Set<String>>{};
    // 每个包：这个包的"前台起点"（集合从空变非空的那一刻）
    final foregroundSince = <String, DateTime>{};

    void accumulate(String pkg, DateTime from, DateTime to) {
      final s = from.isBefore(rangeStart) ? rangeStart : from;
      final e = to.isAfter(rangeEnd) ? rangeEnd : to;
      if (e.isAfter(s)) {
        totals[pkg] = (totals[pkg] ?? 0) + e.difference(s).inMilliseconds;
      }
    }

    for (final ev in events) {
      final pkg = ev.pkg;
      final cls = ev.cls ?? pkg;

      switch (ev.type) {
        case FgEventType.resumed:
          final classes = resumedClasses.putIfAbsent(pkg, () => <String>{});
          if (classes.isEmpty) foregroundSince[pkg] = ev.at;
          classes.add(cls);

        case FgEventType.pausedOrStopped:
          final classes = resumedClasses[pkg];
          if (classes == null) continue;
          // 按类名移除：PAUSED 和 STOPPED 重复到达时不会双算，
          // 且同包别的 Activity 还在前台时不会误断
          if (classes.remove(cls) && classes.isEmpty) {
            final since = foregroundSince.remove(pkg);
            if (since != null) accumulate(pkg, since, ev.at);
          }
      }
    }

    // 到窗口结束时还在前台的
    foregroundSince.forEach((pkg, since) {
      accumulate(pkg, since, rangeEnd);
    });

    return totals;
  }
}
