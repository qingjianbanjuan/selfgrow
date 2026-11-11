import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'presets.dart';

/// 全局状态：属性 / 分组 / 行为 / 记录 / 每日评价
class GameStore extends ChangeNotifier {
  static const _kAttrs = 'sg_attrs_v1';
  static const _kGroups = 'sg_groups_v1';
  static const _kActions = 'sg_actions_v1';
  static const _kLogs = 'sg_logs_v1';
  static const _kMeta = 'sg_meta_v1';

  List<AttrGroup> groups = [];
  List<Attribute> attrs = [];
  List<ActionDef> actions = [];
  List<LogEntry> logs = [];

  DateTime? lastAskedAt; // 上次追问时间
  DateTime? lastLoggedAt; // 上次记录时间
  DateTime? lastDecayAt; // 上次衰减结算
  DateTime? lastSleepStart; // 昨晚入睡时刻（放下手机）
  DateTime? lastSleepEnd; // 昨晚醒来时刻

  // AI 每日评价缓存（按 日期 + 今日记录指纹 失效）
  String? commentHeadline;
  String? commentBody;
  String? commentPraise;
  String? commentReflect;
  List<String> commentHighlights = [];
  String? commentDate;

  /// 生成时的记录指纹（比"条数"严格：增删换都算变化）
  String? commentFingerprint;
  DateTime? commentAt;

  bool loaded = false;

  /// 每天 4:00 作为分界（凌晨记的事算前一天）
  static DateTime dayStart([DateTime? t]) {
    final now = t ?? DateTime.now();
    final d = DateTime(now.year, now.month, now.day, 4);
    return now.isBefore(d) ? d.subtract(const Duration(days: 1)) : d;
  }

  // ---------------- 查询 ----------------

  Attribute? attr(String id) {
    for (final a in attrs) {
      if (a.id == id) return a;
    }
    return null;
  }

  AttrGroup? group(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<Attribute> attrsOf(String groupId, {bool onlyEnabled = true}) {
    final list = attrs
        .where((a) => a.groupId == groupId && (!onlyEnabled || a.enabled))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  List<AttrGroup> get sortedGroups {
    final list = groups.toList()..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// 某组平均进度 0..1（能力型看等级，状态型看数值）
  double groupProgress(String groupId) {
    final list = attrsOf(groupId);
    if (list.isEmpty) return 0;
    return list.fold<double>(0, (p, a) => p + a.normalized) / list.length;
  }

  /// 某组的能力型平均等级（状态型不参与）
  double groupLevel(String groupId) {
    final list = attrsOf(groupId).where((a) => !a.isState).toList();
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (p, a) => p + a.level);
    return sum / list.length;
  }

  /// 综合等级：只由「能力型」属性决定
  int get overallLevel {
    final list = attrs.where((a) => a.enabled && !a.isState).toList();
    if (list.isEmpty) return 1;
    final sum = list.fold<int>(0, (p, a) => p + a.level);
    return (sum / list.length).floor().clamp(1, 999);
  }

  /// 综合等级的小数部分，用于进度条
  double get overallAvgLevel {
    final list = attrs.where((a) => a.enabled && !a.isState).toList();
    if (list.isEmpty) return 1;
    final sum = list.fold<int>(0, (p, a) => p + a.level);
    return sum / list.length;
  }

  /// 状态型属性的平均数值 0..100
  double get stateAverage {
    final list = attrs.where((a) => a.enabled && a.isState).toList();
    if (list.isEmpty) return 0;
    return list.fold<double>(0, (p, a) => p + a.value) / list.length;
  }

  /// 状态型属性的平均归一值 0..1
  double get stateNormalized => (stateAverage / 100).clamp(0.0, 1.0);

  /// 能力型属性的平均归一值 0..1（用于顶部总进度条）
  double get abilityProgress {
    final list = attrs.where((a) => a.enabled && !a.isState).toList();
    if (list.isEmpty) return 0;
    return list.fold<double>(0, (p, a) => p + a.normalized) / list.length;
  }

  bool get hasState => attrs.any((a) => a.enabled && a.isState);

  int get totalExp => attrs.fold<int>(0, (p, a) => p + a.exp);

  List<LogEntry> get logsToday {
    final start = dayStart();
    return logs.where((l) => l.time.isAfter(start)).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
  }

  /// 今天某个属性的净变化
  int todayDelta(String attrId) {
    var d = 0;
    for (final l in logsToday) {
      for (final e in l.effects) {
        if (e.attrId == attrId) d += e.delta;
      }
    }
    return d;
  }

  int get todayCount => logsToday.length;

  Duration get todayActiveSpan {
    final list = logsToday;
    if (list.isEmpty) return Duration.zero;
    final newest = list.first.time;
    final oldest = list.last.time;
    return newest.difference(oldest);
  }

  // ---------------- 生命周期 ----------------

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();

    List<T> decodeList<T>(String key, T Function(Map<String, dynamic>) from) {
      final raw = sp.getString(key);
      if (raw == null || raw.isEmpty) return <T>[];
      try {
        final arr = jsonDecode(raw) as List;
        return arr
            .map((e) => from(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        return <T>[];
      }
    }

    groups = decodeList(_kGroups, AttrGroup.fromJson);
    attrs = decodeList(_kAttrs, Attribute.fromJson);
    actions = decodeList(_kActions, ActionDef.fromJson);
    logs = decodeList(_kLogs, LogEntry.fromJson);

    if (groups.isEmpty) groups = defaultGroups();
    if (attrs.isEmpty) attrs = attributesFromSeeds();
    if (actions.isEmpty) actions = defaultActions();

    final metaRaw = sp.getString(_kMeta);
    if (metaRaw != null) {
      try {
        final m = jsonDecode(metaRaw) as Map<String, dynamic>;
        lastAskedAt = _dt(m['asked']);
        lastLoggedAt = _dt(m['logged']);
        lastDecayAt = _dt(m['decay']);
        lastSleepStart = _dt(m['sleepStart']);
        lastSleepEnd = _dt(m['sleepEnd']);
        commentHeadline = m['ch'] as String?;
        commentBody = m['cb'] as String?;
        commentPraise = m['cp'] as String?;
        commentReflect = m['cr'] as String?;
        commentDate = m['cd'] as String?;
        commentFingerprint = m['cf'] as String?;
        commentAt = _dt(m['ca']);
        final h = m['chl'];
        if (h is List) commentHighlights = h.map((e) => '$e').toList();
      } catch (_) {}
    }

    loaded = true;
    notifyListeners();
    await applyDecay();
  }

  static DateTime? _dt(dynamic v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _kGroups, jsonEncode(groups.map((e) => e.toJson()).toList()));
    await sp.setString(
        _kAttrs, jsonEncode(attrs.map((e) => e.toJson()).toList()));
    await sp.setString(
        _kActions, jsonEncode(actions.map((e) => e.toJson()).toList()));
    await sp.setString(
        _kLogs, jsonEncode(logs.map((e) => e.toJson()).toList()));
    await sp.setString(
        _kMeta,
        jsonEncode({
          'asked': lastAskedAt?.millisecondsSinceEpoch,
          'logged': lastLoggedAt?.millisecondsSinceEpoch,
          'decay': lastDecayAt?.millisecondsSinceEpoch,
          'sleepStart': lastSleepStart?.millisecondsSinceEpoch,
          'sleepEnd': lastSleepEnd?.millisecondsSinceEpoch,
          'ch': commentHeadline,
          'cb': commentBody,
          'cp': commentPraise,
          'cr': commentReflect,
          'chl': commentHighlights,
          'cd': commentDate,
          'cf': commentFingerprint,
          'ca': commentAt?.millisecondsSinceEpoch,
        }));
  }

  // ---------------- 衰减结算 ----------------

  /// 每天第一次打开时结算一次
  Future<void> applyDecay() async {
    final now = DateTime.now();
    if (lastDecayAt == null) {
      lastDecayAt = now;
      await save();
      return;
    }
    final elapsed = now.difference(lastDecayAt!);
    final days = elapsed.inHours ~/ 24;
    if (days < 1) return;

    final windowStart = now.subtract(Duration(days: days));
    for (final a in attrs) {
      if (a.decayPerDay <= 0) continue;
      // 窗口内有没有正向记录
      // - 能力型：有正向增长就不掉
      // - 状态型：默认照掉；但 decayEvenIfLogged=false 的（如睡眠）有记录就不掉
      final needCheck = !a.decayAlways || !a.decayEvenIfLogged;
      if (needCheck) {
        var hasPositive = false;
        for (final l in logs) {
          if (l.time.isBefore(windowStart)) continue;
          for (final e in l.effects) {
            if (e.attrId == a.id && e.delta > 0) {
              hasPositive = true;
              break;
            }
          }
          if (hasPositive) break;
        }
        if (hasPositive) continue;
      }
      final loss = (a.decayPerDay * days).round();
      a.exp = a.clampExp(a.exp - loss);
    }
    lastDecayAt = now;
    await save();
    notifyListeners();
  }

  // ---------------- 写入记录 ----------------

  Future<LogEntry?> applyEffects({
    required String label,
    required String emoji,
    required List<Effect> effects,
    String source = 'manual',
    String? rawText,
    String? summary,
    DateTime? time,
  }) async {
    final valid = <Effect>[];
    for (final e in effects) {
      final a = attr(e.attrId);
      if (a == null) continue;
      final next = a.clampExp(a.exp + e.delta);
      final real = next - a.exp;
      if (real == 0) continue;
      a.exp = next;
      valid.add(Effect(e.attrId, real));
    }
    if (valid.isEmpty) return null;

    final entry = LogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      time: time ?? DateTime.now(),
      label: label,
      emoji: emoji,
      effects: valid,
      source: source,
      rawText: rawText,
      summary: summary,
    );
    logs.add(entry);
    lastLoggedAt = DateTime.now();
    await save();
    notifyListeners();
    return entry;
  }

  Future<void> undo(LogEntry entry) async {
    for (final e in entry.effects) {
      final a = attr(e.attrId);
      if (a == null) continue;
      a.exp = a.clampExp(a.exp - e.delta);
    }
    logs.removeWhere((l) => l.id == entry.id);
    await save();
    notifyListeners();
  }

  // ---------------- 属性/分组管理 ----------------

  Future<void> addAttribute({
    required String name,
    required String groupId,
    String emoji = '✨',
    AttrKind kind = AttrKind.ability,
    int? exp,
    double decay = 0,
  }) async {
    final id = 'u_${DateTime.now().microsecondsSinceEpoch}';
    attrs.add(Attribute(
      id: id,
      groupId: groupId,
      name: name,
      emoji: emoji,
      kind: kind,
      exp: exp ??
          (kind == AttrKind.state ? kStateInitial : kAbilityInitial),
      decayPerDay: decay,
      order: attrs.length,
    ));
    await save();
    notifyListeners();
  }

  Future<void> updateAttribute(Attribute a) async {
    await save();
    notifyListeners();
  }

  Future<void> removeAttribute(String id) async {
    attrs.removeWhere((a) => a.id == id);
    await save();
    notifyListeners();
  }

  Future<AttrGroup> addGroup(String name, {String emoji = '📁'}) async {
    const palette = [
      0xFFEF5350,
      0xFF42A5F5,
      0xFFAB47BC,
      0xFF26C6DA,
      0xFFFFA726,
      0xFFEC407A,
      0xFF66BB6A,
      0xFF8D6E63,
    ];
    final g = AttrGroup(
      id: 'g_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      emoji: emoji,
      colorValue: palette[groups.length % palette.length],
      order: groups.length,
    );
    groups.add(g);
    await save();
    notifyListeners();
    return g;
  }

  /// 找到同名分组，没有就建一个
  Future<AttrGroup> ensureGroup(String name) async {
    for (final g in groups) {
      if (g.name == name) return g;
    }
    return addGroup(name);
  }

  Future<void> removeGroup(String id) async {
    attrs.removeWhere((a) => a.groupId == id);
    groups.removeWhere((g) => g.id == id);
    await save();
    notifyListeners();
  }

  // ---------------- 追问节流 ----------------

  /// 距离上次事件结束过了多久
  Duration get sinceLastEvent {
    final t = lastLoggedAt;
    if (t == null) return const Duration(hours: 6);
    return DateTime.now().difference(t);
  }

  bool get shouldAsk {
    if (lastLoggedAt == null) return false;
    if (sinceLastEvent < const Duration(minutes: 30)) return false;
    final asked = lastAskedAt;
    if (asked != null &&
        DateTime.now().difference(asked) < const Duration(minutes: 30)) {
      return false;
    }
    return true;
  }

  /// 追问的起点 = 上一条记录的时间（最多回溯 12 小时）
  DateTime? get askSince {
    final last = lastLoggedAt;
    if (last == null) return null;
    final maxGap = DateTime.now().subtract(const Duration(hours: 12));
    return last.isBefore(maxGap) ? maxGap : last;
  }

  /// 从起点到现在过了多久
  Duration? get askGap {
    final s = askSince;
    if (s == null) return null;
    return DateTime.now().difference(s);
  }

  /// 这段睡眠是不是还没记过
  bool shouldRecordSleepEnd(DateTime sleepTo) {
    final last = lastSleepEnd;
    if (last == null) return true;
    // 至少要比上次记录的时间晚 30 分钟，才算新的一段睡眠
    return sleepTo.difference(last) > const Duration(minutes: 30);
  }

  /// 保存昨晚这段睡眠（更晚的覆盖旧的）
  Future<void> markSleepRecorded(DateTime sleepFrom, DateTime sleepTo) async {
    lastSleepStart = sleepFrom;
    lastSleepEnd = sleepTo;
    await save();
  }

  /// 上次保存的睡眠时长
  Duration? get savedSleepDuration {
    final a = lastSleepStart;
    final b = lastSleepEnd;
    if (a == null || b == null) return null;
    final d = b.difference(a);
    return d.inMinutes < 30 ? null : d;
  }

  /// 上次保存的睡眠文本，如「02:10 → 08:40（6 小时 30 分）」
  String? get savedSleepText {
    final a = lastSleepStart;
    final b = lastSleepEnd;
    if (a == null || b == null) return null;
    final d = b.difference(a);
    if (d.inMinutes < 30) return null;
    String hhmm(DateTime x) =>
        '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final dur = h <= 0 ? '$m 分钟' : (m > 0 ? '$h 小时 $m 分' : '$h 小时');
    return '${hhmm(a)} 放下手机 → ${hhmm(b)} 拿起（$dur）';
  }

  Future<void> markAsked() async {
    lastAskedAt = DateTime.now();
    await save();
  }

  // ---------------- 快照导出 / 导入 ----------------

  /// 完整快照（JSON 文本）
  String exportSnapshot() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'groups': groups.map((e) => e.toJson()).toList(),
      'attrs': attrs.map((e) => e.toJson()).toList(),
      'actions': actions.map((e) => e.toJson()).toList(),
      'logs': logs.map((e) => e.toJson()).toList(),
      'meta': {
        'asked': lastAskedAt?.millisecondsSinceEpoch,
        'logged': lastLoggedAt?.millisecondsSinceEpoch,
        'decay': lastDecayAt?.millisecondsSinceEpoch,
        'sleepEnd': lastSleepEnd?.millisecondsSinceEpoch,
      },
    });
  }

  /// 从快照恢复（覆盖当前全部数据）
  Future<bool> importSnapshot(String raw) async {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;

      final attrList = (j['attrs'] as List?) ?? [];
      if (attrList.isEmpty) return false;

      final groupList = (j['groups'] as List?) ?? [];
      groups = groupList
          .map((e) => AttrGroup.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      attrs = attrList
          .map((e) => Attribute.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final actionList = (j['actions'] as List?) ?? [];
      if (actionList.isNotEmpty) {
        actions = actionList
            .map((e) => ActionDef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final logList = (j['logs'] as List?) ?? [];
      logs = logList
          .map((e) => LogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final m = j['meta'];
      if (m is Map<String, dynamic>) {
        lastAskedAt = _dt(m['asked']);
        lastLoggedAt = _dt(m['logged']);
        lastDecayAt = _dt(m['decay']);
        lastSleepStart = _dt(m['sleepStart']);
        lastSleepEnd = _dt(m['sleepEnd']);
      }

      if (groups.isEmpty) groups = defaultGroups();
      if (actions.isEmpty) actions = defaultActions();

      await save();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[selfgrow] import failed: $e');
      return false;
    }
  }

  // ---------------- AI 评价缓存 ----------------

  /// 今天记录的指纹：条数 + 所有 id。任何增/删/换都会变。
  String get todayFingerprint {
    final list = logsToday;
    if (list.isEmpty) return '0';
    final ids = list.map((l) => l.id).toList()..sort();
    return '${list.length}|${ids.join(',')}';
  }

  bool get commentStale {
    if (commentBody == null || commentBody!.isEmpty) return true;
    if (commentDate != dayKey()) return true;
    // 用指纹而不是条数：撤销一条再记一条，条数一样但内容不同
    if (commentFingerprint != todayFingerprint) return true;
    final at = commentAt;
    if (at != null &&
        DateTime.now().difference(at) > const Duration(minutes: 30)) {
      return true;
    }
    return false;
  }

  /// 距今多久（用于"生成于 x 分钟前"）
  String get commentAgeText {
    final at = commentAt;
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    return '${d.inHours} 小时前';
  }

  static String dayKey([DateTime? t]) {
    final d = dayStart(t);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> storeComment({
    required String headline,
    required String body,
    required List<String> highlights,
    String? praise,
    String? reflect,
  }) async {
    commentHeadline = headline;
    commentBody = body;
    commentPraise = praise;
    commentReflect = reflect;
    commentHighlights = highlights;
    commentDate = dayKey();
    commentFingerprint = todayFingerprint;
    commentAt = DateTime.now();
    await save();
    notifyListeners();
  }
}
