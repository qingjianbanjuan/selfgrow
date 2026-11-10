import 'package:flutter_test/flutter_test.dart';
import 'package:selfgrow/core/models.dart';
import 'package:selfgrow/core/presets.dart';

void main() {
  group('Attribute 等级计算', () {
    test('从 0 经验开始是 Lv.1', () {
      final a = Attribute(
          id: 'x', groupId: 'body', name: '测试', emoji: '🧪', exp: 0);
      expect(a.level, 1);
      expect(a.expInLevel, 0);
      expect(a.progress, 0.0);
    });

    test('150 经验是 Lv.2 且进度 50%', () {
      final a = Attribute(
          id: 'x', groupId: 'body', name: '测试', emoji: '🧪', exp: 150);
      expect(a.level, 2);
      expect(a.expInLevel, 50);
      expect(a.progress, closeTo(0.5, 1e-9));
    });

    test('负经验不会低于 Lv.1', () {
      final a = Attribute(
          id: 'x', groupId: 'body', name: '测试', emoji: '🧪', exp: -30);
      expect(a.level, 1);
      expect(a.progress, 0.0);
      expect(a.expInLevel, 0);
    });
  });

  group('JSON 往返', () {
    test('Attribute 序列化保持所有字段', () {
      final a = Attribute(
        id: 'hygiene',
        groupId: 'body',
        name: '卫生',
        emoji: '🧼',
        exp: 42,
        enabled: false,
        decayPerDay: 12,
        decayAlways: true,
        order: 5,
      );
      final b = Attribute.fromJson(a.toJson());
      expect(b.id, 'hygiene');
      expect(b.groupId, 'body');
      expect(b.name, '卫生');
      expect(b.emoji, '🧼');
      expect(b.exp, 42);
      expect(b.enabled, false);
      expect(b.decayPerDay, 12);
      expect(b.decayAlways, true);
      expect(b.order, 5);
    });

    test('Effect 序列化', () {
      const e = Effect('stamina', 8);
      final back = Effect.fromJson(e.toJson());
      expect(back.attrId, 'stamina');
      expect(back.delta, 8);
    });
  });

  group('默认种子', () {
    test('8 个分组 / 37 个属性 / 18 个行为', () {
      expect(defaultGroups().length, 8);
      expect(defaultAttrSeeds().length, 37);
      expect(defaultActions().length, 18);
    });

    test('包含用户点名的英语、编程、卫生', () {
      final names = defaultAttrSeeds().map((s) => s.name).toSet();
      expect(names.contains('英语'), true);
      expect(names.contains('编程'), true);
      expect(names.contains('卫生'), true);
    });

    test('卫生是状态型：每天固定衰减', () {
      final s = defaultAttrSeeds().firstWhere((x) => x.name == '卫生');
      expect(s.decayAlways, true);
      expect(s.decay, greaterThan(0));
    });

    test('英语是积累型：不用才掉，且速率很慢', () {
      final s = defaultAttrSeeds().firstWhere((x) => x.name == '英语');
      expect(s.decayAlways, false);
      expect(s.decay, greaterThan(0));
      expect(s.decay, lessThanOrEqualTo(0.5));
    });

    test('所有属性 id 唯一', () {
      final ids = defaultAttrSeeds().map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('所有行为 id 唯一且都能映射到已有属性', () {
      final actionIds = defaultActions().map((a) => a.id).toList();
      expect(actionIds.toSet().length, actionIds.length);

      final attrIds = defaultAttrSeeds().map((s) => s.id).toSet();
      for (final a in defaultActions()) {
        for (final e in a.effects) {
          expect(attrIds.contains(e.attrId), true,
              reason: '行为「${a.name}」引用了不存在的属性 ${e.attrId}');
        }
      }
    });
  });
}
