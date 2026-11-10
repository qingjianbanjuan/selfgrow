import 'package:flutter_test/flutter_test.dart';
import 'package:selfgrow/core/models.dart';
import 'package:selfgrow/core/presets.dart';

void main() {
  group('能力型属性', () {
    test('从 0 经验开始是 Lv.1', () {
      final a = Attribute(
          id: 'x', groupId: 'body', name: '测试', emoji: '🧪', exp: 0);
      expect(a.isState, false);
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

    test('能力型不设上限', () {
      final a = Attribute(
          id: 'x', groupId: 'body', name: '测试', emoji: '🧪', exp: 5000);
      expect(a.clampExp(5000), 5000);
    });
  });

  group('状态型属性', () {
    Attribute mk(int v) => Attribute(
          id: 'hygiene',
          groupId: 'body',
          name: '卫生',
          emoji: '🧼',
          kind: AttrKind.state,
          exp: v,
        );

    test('没有等级概念，只有数值', () {
      final a = mk(85);
      expect(a.isState, true);
      expect(a.value, 85);
      expect(a.stateLabel, '良好');
      expect(a.primaryText, '85');
    });

    test('数值钳制在 0..100', () {
      expect(mk(-50).value, 0);
      expect(mk(150).value, 100);
      expect(mk(150).clampExp(150), 100);
      expect(mk(-50).clampExp(-50), 0);
    });

    test('状态分区间的文案', () {
      expect(mk(95).stateLabel, '很好');
      expect(mk(80).stateLabel, '良好');
      expect(mk(65).stateLabel, '及格');
      expect(mk(50).stateLabel, '偏低');
      expect(mk(30).stateLabel, '很差');
      expect(mk(10).stateLabel, '告急');
    });

    test('默认起始在及格线，不是 0', () {
      final a = mk(kStateInitial);
      expect(kStateInitial, 60);
      expect(a.value, 60);
      expect(a.stateLabel, '及格');
    });

    test('状态型每天固定衰减', () {
      expect(mk(80).decayAlways, true);
    });
  });

  group('JSON 往返', () {
    test('能力型保持所有字段', () {
      final a = Attribute(
        id: 'english',
        groupId: 'lang',
        name: '英语',
        emoji: '🇬🇧',
        kind: AttrKind.ability,
        exp: 42,
        enabled: false,
        decayPerDay: 0.3,
        order: 5,
      );
      final b = Attribute.fromJson(a.toJson());
      expect(b.id, 'english');
      expect(b.kind, AttrKind.ability);
      expect(b.exp, 42);
      expect(b.enabled, false);
      expect(b.decayPerDay, 0.3);
      expect(b.order, 5);
    });

    test('状态型 kind 能还原', () {
      final a = Attribute(
          id: 'mood',
          groupId: 'emotion',
          name: '心情',
          emoji: '😊',
          kind: AttrKind.state,
          exp: 72);
      final b = Attribute.fromJson(a.toJson());
      expect(b.kind, AttrKind.state);
      expect(b.value, 72);
    });

    test('兼容旧数据（只有 da 字段）', () {
      final legacy = {
        'id': 'hygiene',
        'g': 'body',
        'n': '卫生',
        'e': '🧼',
        'x': 40,
        'on': 1,
        'd': 12,
        'da': 1,
        'o': 5,
      };
      final b = Attribute.fromJson(legacy);
      expect(b.kind, AttrKind.state);
      expect(b.value, 40);
    });
  });

  group('默认种子', () {
    test('8 分组 / 37 属性 / 18 行为', () {
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

    test('状态型属性有 10 个，且都不是能力', () {
      final states =
          defaultAttrSeeds().where((s) => s.kind == AttrKind.state).toList();
      expect(states.length, 10);
      final names = states.map((s) => s.name).toSet();
      expect(
          names,
          containsAll([
            '体力',
            '卫生',
            '专注',
            '心情',
            '稳定',
            '抗压',
            '意志',
            '睡眠',
            '饮食',
            '健康',
          ]));
    });

    test('所有状态型初始值都是及格线 60', () {
      for (final s
          in defaultAttrSeeds().where((s) => s.kind == AttrKind.state)) {
        expect(s.initExp, 60, reason: '${s.name} 初始值应为 60');
      }
    });

    test('所有状态型都有衰减，且衰减 > 0', () {
      for (final s
          in defaultAttrSeeds().where((s) => s.kind == AttrKind.state)) {
        expect(s.decay, greaterThan(0), reason: '${s.name} 应该有衰减');
      }
    });

    test('能力型初始值是 0', () {
      for (final s
          in defaultAttrSeeds().where((s) => s.kind == AttrKind.ability)) {
        expect(s.initExp, 0, reason: '${s.name} 初始经验应为 0');
      }
    });

    test('英语有缓慢衰减（会忘，但很慢）', () {
      final s = defaultAttrSeeds().firstWhere((x) => x.name == '英语');
      expect(s.kind, AttrKind.ability);
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

    test('转换出的属性对象：状态型起始 60，能力型 Lv.1', () {
      final list = attributesFromSeeds();
      expect(list.length, 37);
      final hygiene = list.firstWhere((a) => a.name == '卫生');
      expect(hygiene.isState, true);
      expect(hygiene.value, 60);
      final english = list.firstWhere((a) => a.name == '英语');
      expect(english.isState, false);
      expect(english.exp, 0);
      expect(english.level, 1);
    });
  });
}
