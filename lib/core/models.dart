import 'dart:convert';

import 'package:flutter/material.dart';

/// 属性分组 —— 可增删改，所以是可变对象
class AttrGroup {
  final String id;
  String name;
  String emoji;
  int colorValue;
  int order;

  AttrGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    required this.order,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'e': emoji,
        'c': colorValue,
        'o': order,
      };

  static AttrGroup fromJson(Map<String, dynamic> j) => AttrGroup(
        id: j['id'] as String,
        name: j['n'] as String,
        emoji: j['e'] as String,
        colorValue: (j['c'] as num).toInt(),
        order: (j['o'] as num?)?.toInt() ?? 0,
      );
}

/// 属性种类 —— 决定"要不要等级"
enum AttrKind {
  /// 能力型：会累积、有等级（英语、编程、力量、阅读…）
  ability,

  /// 状态型：有当前值 0~100、没有等级（心情、卫生、睡眠、体力…）
  state,
}

/// 属性 —— 数据而非常量，用户可以随意增删改
class Attribute {
  final String id;
  String groupId;
  String name;
  String emoji;

  /// 属性种类：
  /// - [AttrKind.ability] 能力型：会累积、有等级（英语/编程/力量…）
  /// - [AttrKind.state]   状态型：有当前值 0~100、无等级（心情/卫生/睡眠…）
  AttrKind kind;

  /// 能力型：累计经验（等级 = exp ~/ 100 + 1）
  /// 状态型：当前值 0~100
  int exp;

  /// 是否在主界面显示（隐藏后数据保留）
  bool enabled;

  /// 每日自然衰减（能力型是经验点，状态型是数值点），0 = 不衰减
  double decayPerDay;

  /// 上次结算衰减的时间
  int? lastDecayAtMs;

  int order;

  Attribute({
    required this.id,
    required this.groupId,
    required this.name,
    required this.emoji,
    this.kind = AttrKind.ability,
    this.exp = 0,
    this.enabled = true,
    this.decayPerDay = 0,
    this.lastDecayAtMs,
    this.order = 0,
  });

  bool get isState => kind == AttrKind.state;

  /// 状态型每天固定衰减；能力型当天有正向增长就不衰减
  bool get decayAlways => isState;

  // ---------------- 能力型 ----------------

  int get level => exp < 0 ? 1 : exp ~/ 100 + 1;

  /// 当前等级内的进度 0..1
  double get progress {
    if (exp < 0) return 0;
    return (exp % 100) / 100.0;
  }

  int get expInLevel => exp < 0 ? 0 : exp % 100;

  // ---------------- 状态型 ----------------

  /// 状态型的当前值，钳在 0..100
  int get value => exp.clamp(0, 100);

  /// 状态文字（无等级，只有区间描述）
  String get stateLabel {
    final v = value;
    if (v >= 88) return '很好';
    if (v >= 72) return '良好';
    if (v >= 60) return '及格';
    if (v >= 42) return '偏低';
    if (v >= 22) return '很差';
    return '告急';
  }

  /// 统一归一 0..1，用于分组条与小人。
  /// 能力型 Lv.1 起步给 0.2 的底（刚上手不等于"一无所有"），Lv.12 满分。
  double get normalized {
    if (isState) return value / 100;
    final n = 0.2 + 0.8 * ((level - 1 + progress) / 11);
    return n.clamp(0.0, 1.0);
  }

  /// 写入前钳制：状态型 0..100，能力型不设上限
  int clampExp(int v) => isState ? v.clamp(0, 100) : v.clamp(0, 1 << 20);

  /// 主界面/明细里显示的"主文本"，能力型返回 Lv，状态型返回值
  String get primaryText => isState ? '$value' : 'Lv.$level';

  Map<String, dynamic> toJson() => {
        'id': id,
        'g': groupId,
        'n': name,
        'e': emoji,
        'k': isState ? 'state' : 'ability',
        'x': exp,
        'on': enabled ? 1 : 0,
        'd': decayPerDay,
        'la': lastDecayAtMs,
        'o': order,
      };

  static Attribute fromJson(Map<String, dynamic> j) {
    final k = j['k'] as String?;
    // 兼容 v0.3.x 的旧数据（只有 da 字段）
    final legacyState = ((j['da'] as num?)?.toInt() ?? 0) == 1;
    final kind = k == 'state'
        ? AttrKind.state
        : (k == 'ability' ? AttrKind.ability : (legacyState ? AttrKind.state : AttrKind.ability));
    return Attribute(
      id: j['id'] as String,
      groupId: j['g'] as String,
      name: j['n'] as String,
      emoji: (j['e'] as String?) ?? '•',
      kind: kind,
      exp: (j['x'] as num?)?.toInt() ?? 0,
      enabled: ((j['on'] as num?)?.toInt() ?? 1) == 1,
      decayPerDay: (j['d'] as num?)?.toDouble() ?? 0,
      lastDecayAtMs: (j['la'] as num?)?.toInt(),
      order: (j['o'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一条属性变化
class Effect {
  final String attrId;
  final int delta;
  const Effect(this.attrId, this.delta);

  Map<String, dynamic> toJson() => {'a': attrId, 'd': delta};

  static Effect fromJson(Map<String, dynamic> j) =>
      Effect(j['a'] as String, (j['d'] as num).toInt());

  @override
  String toString() => '$attrId${delta >= 0 ? '+' : ''}$delta';
}

/// 行为模板
class ActionDef {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final List<Effect> effects;
  final bool custom;

  ActionDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.effects,
    this.custom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'e': emoji,
        'c': category,
        'f': effects.map((e) => e.toJson()).toList(),
      };

  static ActionDef fromJson(Map<String, dynamic> j) => ActionDef(
        id: j['id'] as String,
        name: j['n'] as String,
        emoji: (j['e'] as String?) ?? '✏️',
        category: (j['c'] as String?) ?? '自定义',
        effects: (j['f'] as List)
            .map((e) => Effect.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        custom: true,
      );
}

/// 一条已生效的记录
class LogEntry {
  final String id;
  final DateTime time;
  final String label;
  final String emoji;
  final List<Effect> effects;
  final String? source; // preset | ai | manual
  final String? rawText;
  final String? summary;

  LogEntry({
    required this.id,
    required this.time,
    required this.label,
    required this.emoji,
    required this.effects,
    this.source,
    this.rawText,
    this.summary,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        't': time.millisecondsSinceEpoch,
        'l': label,
        'e': emoji,
        'f': effects.map((e) => e.toJson()).toList(),
        's': source,
        'r': rawText,
        'm': summary,
      };

  static LogEntry fromJson(Map<String, dynamic> j) => LogEntry(
        id: j['id'] as String,
        time: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        label: j['l'] as String,
        emoji: (j['e'] as String?) ?? '•',
        effects: (j['f'] as List)
            .map((e) => Effect.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        source: j['s'] as String?,
        rawText: j['r'] as String?,
        summary: j['m'] as String?,
      );
}

/// AI 建议新建的属性
class SuggestedAttr {
  final String name;
  final String group;
  final String emoji;
  final int initExp;

  SuggestedAttr({
    required this.name,
    this.group = '自定义',
    this.emoji = '✨',
    this.initExp = 0,
  });

  static SuggestedAttr fromJson(Map<String, dynamic> j) => SuggestedAttr(
        name: (j['name'] ?? '').toString(),
        group: (j['group'] ?? '自定义').toString(),
        emoji: (j['emoji'] ?? '✨').toString(),
        initExp: (j['init_exp'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'group': group,
        'emoji': emoji,
        'init_exp': initExp,
      };
}

/// AI 判定结果
class AiJudgement {
  final List<Effect> effects;
  final List<SuggestedAttr> suggestions;
  final String summary;
  final String emoji;
  final String? reasoning;

  AiJudgement({
    required this.effects,
    required this.summary,
    this.suggestions = const [],
    this.emoji = '🤖',
    this.reasoning,
  });
}

/// 手机使用摘要（给 AI 用）
class AppUsageBrief {
  final String packageName;
  final String appName;
  final Duration duration;
  AppUsageBrief(this.packageName, this.appName, this.duration);

  String get label {
    final m = duration.inMinutes;
    if (m < 1) return '$appName ${duration.inSeconds}秒';
    if (m < 60) return '$appName $m分钟';
    return '$appName ${(m / 60).toStringAsFixed(1)}小时';
  }

  @override
  String toString() => label;
}

/// 便于调试与日志
String dumpJson(Object o) => const JsonEncoder.withIndent('  ').convert(o);
