import 'models.dart';

/// 状态型属性的初始值（及格线）
const int kStateInitial = 60;

/// 能力型属性的初始经验
const int kAbilityInitial = 0;

/// 默认属性种子 —— 只是"初始数据"，用户可随意增删改
class AttrSeed {
  final String id;
  final String groupId;
  final String name;
  final String emoji;
  final AttrKind kind;

  /// 每日衰减（能力型=经验点，状态型=数值点）
  final double decay;

  /// 初始值：状态型默认 60（及格线），能力型默认 0
  final int initExp;

  const AttrSeed(
    this.id,
    this.groupId,
    this.name,
    this.emoji,
    this.kind, {
    this.decay = 0,
    int? initExp,
  }) : initExp = initExp ??
            (kind == AttrKind.state ? kStateInitial : kAbilityInitial);
}

/// 8 个默认分组
List<AttrGroup> defaultGroups() => [
      AttrGroup(
          id: 'body', name: '身体', emoji: '💪', colorValue: 0xFFEF5350, order: 0),
      AttrGroup(
          id: 'mind', name: '头脑', emoji: '🧠', colorValue: 0xFF42A5F5, order: 1),
      AttrGroup(
          id: 'lang', name: '语言', emoji: '🗣️', colorValue: 0xFFAB47BC, order: 2),
      AttrGroup(
          id: 'skill', name: '技能', emoji: '🛠️', colorValue: 0xFF26C6DA, order: 3),
      AttrGroup(
          id: 'social', name: '社交', emoji: '🤝', colorValue: 0xFFFFA726, order: 4),
      AttrGroup(
          id: 'emotion', name: '情绪', emoji: '💗', colorValue: 0xFFEC407A, order: 5),
      AttrGroup(
          id: 'life', name: '生活', emoji: '🏠', colorValue: 0xFF66BB6A, order: 6),
      AttrGroup(
          id: 'aesthetic', name: '审美', emoji: '🎨', colorValue: 0xFF8D6E63, order: 7),
    ];

/// 37 个默认属性
///
/// 状态型（state，10 个）：体力 / 卫生 / 专注 / 心情 / 稳定 / 抗压 / 意志 / 睡眠 / 饮食 / 健康
/// 能力型（ability，27 个）：其余
List<AttrSeed> defaultAttrSeeds() => const [
      // ===== 身体 =====
      // 体力、卫生、健康是"当前状态"，会掉，没有等级
      AttrSeed('stamina', 'body', '体力', '💪', AttrKind.state, decay: 8),
      AttrSeed('strength', 'body', '力量', '🏋️', AttrKind.ability, decay: 2.0),
      AttrSeed('endurance', 'body', '耐力', '🏃', AttrKind.ability, decay: 2.0),
      AttrSeed('agility', 'body', '灵敏', '🤸', AttrKind.ability, decay: 1.5),
      AttrSeed('health', 'body', '健康', '❤️', AttrKind.state, decay: 1.5),
      AttrSeed('hygiene', 'body', '卫生', '🧼', AttrKind.state, decay: 12),

      // ===== 头脑 =====
      AttrSeed('intellect', 'mind', '智力', '🧠', AttrKind.ability, decay: 0.4),
      AttrSeed('focus', 'mind', '专注', '🎯', AttrKind.state, decay: 6),
      AttrSeed('memory', 'mind', '记忆', '🧩', AttrKind.ability, decay: 0.4),
      AttrSeed('logic', 'mind', '逻辑', '🔗', AttrKind.ability, decay: 0.4),
      AttrSeed('learning', 'mind', '学习', '📚', AttrKind.ability, decay: 0.8),

      // ===== 语言 =====
      AttrSeed('english', 'lang', '英语', '🇬🇧', AttrKind.ability, decay: 0.3),
      AttrSeed('expression', 'lang', '表达', '🗣️', AttrKind.ability, decay: 0.4),
      AttrSeed('writing', 'lang', '写作', '✍️', AttrKind.ability, decay: 0.8),
      AttrSeed('reading', 'lang', '阅读', '📖', AttrKind.ability, decay: 0.8),
      AttrSeed('speaking', 'lang', '演讲', '🎤', AttrKind.ability, decay: 1.0),

      // ===== 技能 =====
      AttrSeed('programming', 'skill', '编程', '💻', AttrKind.ability, decay: 0.4),
      AttrSeed('professional', 'skill', '专业', '🎓', AttrKind.ability, decay: 0.4),
      AttrSeed('efficiency', 'skill', '效率', '⚡', AttrKind.ability, decay: 1.0),
      AttrSeed('handson', 'skill', '动手', '🔧', AttrKind.ability, decay: 0.8),

      // ===== 社交 =====
      AttrSeed('affinity', 'social', '亲和', '🤝', AttrKind.ability, decay: 1.0),
      AttrSeed('empathy', 'social', '共情', '💞', AttrKind.ability, decay: 1.0),
      AttrSeed('communication', 'social', '沟通', '💬', AttrKind.ability,
          decay: 1.0),
      AttrSeed('influence', 'social', '影响', '📣', AttrKind.ability, decay: 0.8),
      AttrSeed('network', 'social', '人脉', '🕸️', AttrKind.ability, decay: 0.8),

      // ===== 情绪（全部是状态）=====
      AttrSeed('mood', 'emotion', '心情', '😊', AttrKind.state, decay: 6),
      AttrSeed('stability', 'emotion', '稳定', '⚖️', AttrKind.state, decay: 2),
      AttrSeed('resilience', 'emotion', '抗压', '🛡️', AttrKind.state, decay: 3),
      AttrSeed('willpower', 'emotion', '意志', '🔥', AttrKind.state, decay: 3),

      // ===== 生活 =====
      AttrSeed('sleep', 'life', '睡眠', '😴', AttrKind.state, decay: 10),
      AttrSeed('diet', 'life', '饮食', '🍚', AttrKind.state, decay: 5),
      AttrSeed('finance', 'life', '财务', '💰', AttrKind.ability, decay: 0.5),
      AttrSeed('order', 'life', '秩序', '🧹', AttrKind.ability, decay: 1.5),
      AttrSeed('discipline', 'life', '自律', '⏰', AttrKind.ability, decay: 1.2),

      // ===== 审美 =====
      AttrSeed('aesthetic', 'aesthetic', '审美', '🎨', AttrKind.ability,
          decay: 0.4),
      AttrSeed('creativity', 'aesthetic', '创造', '💡', AttrKind.ability,
          decay: 0.5),
      AttrSeed('design', 'aesthetic', '设计', '🖌️', AttrKind.ability, decay: 0.5),
    ];

/// 把种子转成可变属性对象
List<Attribute> attributesFromSeeds() {
  final seeds = defaultAttrSeeds();
  final list = <Attribute>[];
  for (var i = 0; i < seeds.length; i++) {
    final s = seeds[i];
    list.add(Attribute(
      id: s.id,
      groupId: s.groupId,
      name: s.name,
      emoji: s.emoji,
      kind: s.kind,
      exp: s.initExp,
      decayPerDay: s.decay,
      order: i,
    ));
  }
  return list;
}

/// 预设行为（一键直记，不走 AI）
List<ActionDef> defaultActions() => [
      ActionDef(
        id: 'run',
        name: '跑步 30 分钟',
        emoji: '🏃',
        category: '运动',
        effects: const [
          Effect('stamina', 8),
          Effect('health', 5),
          Effect('strength', 2),
          Effect('endurance', 6),
          Effect('mood', 3),
          Effect('hygiene', -8),
        ],
      ),
      ActionDef(
        id: 'gym',
        name: '力量训练',
        emoji: '🏋️',
        category: '运动',
        effects: const [
          Effect('strength', 9),
          Effect('stamina', 4),
          Effect('health', 3),
          Effect('hygiene', -6),
        ],
      ),
      ActionDef(
        id: 'walk',
        name: '散步 20 分钟',
        emoji: '🚶',
        category: '运动',
        effects: const [
          Effect('stamina', 3),
          Effect('health', 3),
          Effect('mood', 2),
        ],
      ),
      ActionDef(
        id: 'read',
        name: '读书 1 小时',
        emoji: '📖',
        category: '学习',
        effects: const [
          Effect('reading', 8),
          Effect('intellect', 4),
          Effect('focus', 5),
          Effect('learning', 5),
          Effect('memory', 3),
        ],
      ),
      ActionDef(
        id: 'english',
        name: '学英语 30 分钟',
        emoji: '🇬🇧',
        category: '学习',
        effects: const [
          Effect('english', 7),
          Effect('memory', 2),
          Effect('learning', 3),
        ],
      ),
      ActionDef(
        id: 'code',
        name: '写代码 1 小时',
        emoji: '💻',
        category: '学习',
        effects: const [
          Effect('programming', 7),
          Effect('logic', 4),
          Effect('focus', 4),
          Effect('creativity', 2),
        ],
      ),
      ActionDef(
        id: 'write',
        name: '写点东西',
        emoji: '✍️',
        category: '学习',
        effects: const [
          Effect('writing', 6),
          Effect('expression', 4),
          Effect('creativity', 3),
        ],
      ),
      ActionDef(
        id: 'shower',
        name: '洗澡',
        emoji: '🚿',
        category: '生活',
        effects: const [
          Effect('hygiene', 15),
          Effect('mood', 4),
          Effect('stamina', 2),
        ],
      ),
      ActionDef(
        id: 'clean',
        name: '整理房间',
        emoji: '🧹',
        category: '生活',
        effects: const [
          Effect('order', 7),
          Effect('discipline', 4),
          Effect('mood', 3),
          Effect('hygiene', 3),
        ],
      ),
      ActionDef(
        id: 'early_sleep',
        name: '早睡',
        emoji: '😴',
        category: '生活',
        effects: const [
          Effect('sleep', 12),
          Effect('mood', 4),
          Effect('stamina', 5),
          Effect('stability', 3),
        ],
      ),
      ActionDef(
        id: 'late_night',
        name: '熬夜',
        emoji: '🦉',
        category: '生活',
        effects: const [
          Effect('sleep', -12),
          Effect('mood', -4),
          Effect('health', -5),
          Effect('focus', -4),
          Effect('stamina', -5),
        ],
      ),
      ActionDef(
        id: 'eat_well',
        name: '好好吃饭',
        emoji: '🍚',
        category: '生活',
        effects: const [
          Effect('diet', 8),
          Effect('stamina', 3),
          Effect('mood', 2),
        ],
      ),
      ActionDef(
        id: 'social',
        name: '和朋友聚',
        emoji: '🎉',
        category: '社交',
        effects: const [
          Effect('affinity', 6),
          Effect('communication', 4),
          Effect('empathy', 3),
          Effect('mood', 5),
        ],
      ),
      ActionDef(
        id: 'deep_talk',
        name: '深聊一场',
        emoji: '💬',
        category: '社交',
        effects: const [
          Effect('communication', 6),
          Effect('empathy', 5),
          Effect('affinity', 4),
        ],
      ),
      ActionDef(
        id: 'meditate',
        name: '冥想 10 分钟',
        emoji: '🧘',
        category: '情绪',
        effects: const [
          Effect('stability', 6),
          Effect('resilience', 5),
          Effect('focus', 3),
          Effect('mood', 3),
        ],
      ),
      ActionDef(
        id: 'phone_scroll',
        name: '刷手机',
        emoji: '📱',
        category: '情绪',
        effects: const [
          Effect('focus', -4),
          Effect('willpower', -3),
          Effect('mood', 1),
        ],
      ),
      ActionDef(
        id: 'accounting',
        name: '记一笔账',
        emoji: '💰',
        category: '生活',
        effects: const [
          Effect('finance', 6),
          Effect('order', 4),
          Effect('discipline', 3),
        ],
      ),
      ActionDef(
        id: 'create',
        name: '做点创作',
        emoji: '🎨',
        category: '审美',
        effects: const [
          Effect('creativity', 7),
          Effect('aesthetic', 5),
          Effect('design', 3),
        ],
      ),
    ];
