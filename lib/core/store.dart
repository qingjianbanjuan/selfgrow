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

  // AI 每日评价缓存（按 日期 + 记录数 失效）
  String? commentHeadline;
  String? commentBody;
  List<String> commentHighlights = [];
  String? commentDate;
  int commentLogCount = -1;
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
        commentHeadline = m['ch'] as String?;
        commentBody = m['cb'] as String?;
        commentDate = m['cd'] as String?;
        commentLogCount = (m['cc'] as num?)?.toInt() ?? -1;
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
          'ch': commentHeadline,
          'cb': commentBody,
          'chl': commentHighlights,
          'cd': commentDate,
          'cc': commentLogCount,
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
      if (!a.decayAlways) {
        // 积累型：窗口内有正向增长就不掉
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
    if (sinceLastEvent < const Duration(minutes: 30)) return false;
    final asked = lastAskedAt;
    if (asked != null && DateTime.now().difference(asked) < const Duration(minutes: 30)) {
      return false;
    }
    return true;
  }

  Future<void> markAsked() async {
    lastAskedAt = DateTime.now();
    await save();
  }

  // ---------------- AI 评价缓存 ----------------

  bool get commentStale {
    if (commentBody == null || commentBody!.isEmpty) return true;
    if (commentDate != dayKey()) return true;
    if (commentLogCount != todayCount) return true;
    final at = commentAt;
    if (at != null && DateTime.now().difference(at) > const Duration(hours: 2)) {
      return true;
    }
    return false;
  }

  static String dayKey([DateTime? t]) {
    final d = dayStart(t);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> storeComment({
    required String headline,
    required String body,
    required List<String> highlights,
  }) async {
    commentHeadline = headline;
    commentBody = body;
    commentHighlights = highlights;
    commentDate = dayKey();
    commentLogCount = todayCount;
    commentAt = DateTime.now();
    await save();
    notifyListeners();
  }
}
