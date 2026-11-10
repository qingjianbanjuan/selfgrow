import 'models.dart';

/// 默认属性种子 —— 只是"初始数据"，用户可随意增删改
///
/// decayAlways = true  -> 状态型：每天固定衰减
/// decayAlways = false -> 积累型：当天有正向增长就不衰减
class AttrSeed {
  final String id;
  final String groupId;
  final String name;
  final String emoji;
  final double decay;
  final bool decayAlways;
  final int initExp;

  const AttrSeed(this.id, this.groupId, this.name, this.emoji, this.decay,
      {this.decayAlways = false, this.initExp = 0});
}

/// 8 个默认分组
List<AttrGroup> defaultGroups() => [
      AttrGroup(id: 'body', name: '身体', emoji: '💪', colorValue: 0xFFEF5350, order: 0),
      AttrGroup(id: 'mind', name: '头脑', emoji: '🧠', colorValue: 0xFF42A5F5, order: 1),
      AttrGroup(id: 'lang', name: '语言', emoji: '🗣️', colorValue: 0xFFAB47BC, order: 2),
      AttrGroup(id: 'skill', name: '技能', emoji: '🛠️', colorValue: 0xFF26C6DA, order: 3),
      AttrGroup(id: 'social', name: '社交', emoji: '🤝', colorValue: 0xFFFFA726, order: 4),
      AttrGroup(id: 'emotion', name: '情绪', emoji: '💗', colorValue: 0xFFEC407A, order: 5),
      AttrGroup(id: 'life', name: '生活', emoji: '🏠', colorValue: 0xFF66BB6A, order: 6),
      AttrGroup(id: 'aesthetic', name: '审美', emoji: '🎨', colorValue: 0xFF8D6E63, order: 7),
    ];

/// 37 个默认属性
List<AttrSeed> defaultAttrSeeds() => const [
      // ===== 身体 =====
      AttrSeed('stamina', 'body', '体力', '💪', 8, decayAlways: true),
      AttrSeed('strength', 'body', '力量', '🏋️', 2.0),
      AttrSeed('endurance', 'body', '耐力', '🏃', 2.0),
      AttrSeed('agility', 'body', '灵敏', '🤸', 1.5),
      AttrSeed('health', 'body', '健康', '❤️', 1.5),
      AttrSeed('hygiene', 'body', '卫生', '🧼', 12, decayAlways: true),

      // ===== 头脑 =====
      AttrSeed('intellect', 'mind', '智力', '🧠', 0.4),
      AttrSeed('focus', 'mind', '专注', '🎯', 6, decayAlways: true),
      AttrSeed('memory', 'mind', '记忆', '🧩', 0.4),
      AttrSeed('logic', 'mind', '逻辑', '🔗', 0.4),
      AttrSeed('learning', 'mind', '学习', '📚', 0.8),

      // ===== 语言 =====
      AttrSeed('english', 'lang', '英语', '🇬🇧', 0.3),
      AttrSeed('expression', 'lang', '表达', '🗣️', 0.4),
      AttrSeed('writing', 'lang', '写作', '✍️', 0.8),
      AttrSeed('reading', 'lang', '阅读', '📖', 0.8),
      AttrSeed('speaking', 'lang', '演讲', '🎤', 1.0),

      // ===== 技能 =====
      AttrSeed('programming', 'skill', '编程', '💻', 0.4),
      AttrSeed('professional', 'skill', '专业', '🎓', 0.4),
      AttrSeed('efficiency', 'skill', '效率', '⚡', 1.0),
      AttrSeed('handson', 'skill', '动手', '🔧', 0.8),

      // ===== 社交 =====
      AttrSeed('affinity', 'social', '亲和', '🤝', 1.0),
      AttrSeed('empathy', 'social', '共情', '💞', 1.0),
      AttrSeed('communication', 'social', '沟通', '💬', 1.0),
      AttrSeed('influence', 'social', '影响', '📣', 0.8),
      AttrSeed('network', 'social', '人脉', '🕸️', 0.8),

      // ===== 情绪 =====
      AttrSeed('mood', 'emotion', '心情', '😊', 6, decayAlways: true),
      AttrSeed('stability', 'emotion', '稳定', '⚖️', 2, decayAlways: true),
      AttrSeed('resilience', 'emotion', '抗压', '🛡️', 3, decayAlways: true),
      AttrSeed('willpower', 'emotion', '意志', '🔥', 3, decayAlways: true),

      // ===== 生活 =====
      AttrSeed('sleep', 'life', '睡眠', '😴', 10, decayAlways: true),
      AttrSeed('diet', 'life', '饮食', '🍚', 5, decayAlways: true),
      AttrSeed('finance', 'life', '财务', '💰', 0.5),
      AttrSeed('order', 'life', '秩序', '🧹', 1.5),
      AttrSeed('discipline', 'life', '自律', '⏰', 1.2),

      // ===== 审美 =====
      AttrSeed('aesthetic', 'aesthetic', '审美', '🎨', 0.4),
      AttrSeed('creativity', 'aesthetic', '创造', '💡', 0.5),
      AttrSeed('design', 'aesthetic', '设计', '🖌️', 0.5),
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
      exp: s.initExp,
      decayPerDay: s.decay,
      decayAlways: s.decayAlways,
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
          Effect('hygiene', -8), // 出汗
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
