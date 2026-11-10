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

/// 属性 —— 数据而非常量，用户可以随意增删改
class Attribute {
  final String id;
  String groupId;
  String name;
  String emoji;

  /// 累积经验；等级 = exp ~/ 100 + 1
  int exp;

  /// 是否在主界面显示（隐藏后数据保留）
  bool enabled;

  /// 每日自然衰减（经验点数，0 = 不衰减）
  double decayPerDay;

  /// true  = 状态型：每天固定衰减（卫生/睡眠/体力…）
  /// false = 积累型：当天有正向增长就不衰减，否则衰减（英语/编程/力量…）
  bool decayAlways;

  /// 上次结算衰减的时间
  int? lastDecayAtMs;

  int order;

  Attribute({
    required this.id,
    required this.groupId,
    required this.name,
    required this.emoji,
    this.exp = 0,
    this.enabled = true,
    this.decayPerDay = 0,
    this.decayAlways = false,
    this.lastDecayAtMs,
    this.order = 0,
  });

  int get level => exp < 0 ? 1 : exp ~/ 100 + 1;

  /// 当前等级内的进度 0..1
  double get progress {
    if (exp < 0) return 0;
    return (exp % 100) / 100.0;
  }

  int get expInLevel => exp < 0 ? 0 : exp % 100;

  Map<String, dynamic> toJson() => {
        'id': id,
        'g': groupId,
        'n': name,
        'e': emoji,
        'x': exp,
        'on': enabled ? 1 : 0,
        'd': decayPerDay,
        'da': decayAlways ? 1 : 0,
        'la': lastDecayAtMs,
        'o': order,
      };

  static Attribute fromJson(Map<String, dynamic> j) => Attribute(
        id: j['id'] as String,
        groupId: j['g'] as String,
        name: j['n'] as String,
        emoji: (j['e'] as String?) ?? '•',
        exp: (j['x'] as num?)?.toInt() ?? 0,
        enabled: ((j['on'] as num?)?.toInt() ?? 1) == 1,
        decayPerDay: (j['d'] as num?)?.toDouble() ?? 0,
        decayAlways: ((j['da'] as num?)?.toInt() ?? 0) == 1,
        lastDecayAtMs: (j['la'] as num?)?.toInt(),
        order: (j['o'] as num?)?.toInt() ?? 0,
      );
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
