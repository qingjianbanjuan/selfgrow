import 'package:flutter_test/flutter_test.dart';
import 'package:selfgrow/core/models.dart';
import 'package:selfgrow/core/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GameStore mkStore() {
    final s = GameStore();
    s.groups = [
      AttrGroup(
          id: 'g', name: '测试', emoji: '🧪', colorValue: 0xFF000000, order: 0),
    ];
    s.attrs = [
      Attribute(
          id: 'mood',
          groupId: 'g',
          name: '心情',
          emoji: '😊',
          kind: AttrKind.state,
          exp: 60),
      Attribute(
          id: 'english',
          groupId: 'g',
          name: '英语',
          emoji: '🇬🇧',
          kind: AttrKind.ability,
          exp: 0),
    ];
    s.actions = [];
    s.logs = [];
    s.loaded = true;
    return s;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('今日评价的失效判断（"今天怎么样"会不会刷新）', () {
    test('没生成过 -> 失效', () {
      final s = mkStore();
      expect(s.commentStale, true);
    });

    test('生成后 -> 不失效', () async {
      final s = mkStore();
      await s.storeComment(headline: '还好', body: '今天没什么', highlights: []);
      expect(s.commentStale, false);
    });

    test('新增一条记录 -> 失效（会重新生成）', () async {
      final s = mkStore();
      await s.storeComment(headline: '还好', body: '今天没什么', highlights: []);
      expect(s.commentStale, false);

      await s.applyEffects(
        label: '学英语',
        emoji: '🇬🇧',
        effects: const [Effect('english', 10)],
        source: 'preset',
      );
      expect(s.commentStale, true);
    });

    test('撤销一条再记一条（条数一样）也要失效', () async {
      final s = mkStore();
      await s.applyEffects(
        label: '学英语',
        emoji: '🇬🇧',
        effects: const [Effect('english', 10)],
        source: 'preset',
      );
      await s.storeComment(headline: '还好', body: '今天没什么', highlights: []);
      expect(s.commentStale, false);

      // 撤销原来那条
      await s.undo(s.logs.first);
      // 再记一条不同的
      await s.applyEffects(
        label: '背单词',
        emoji: '📖',
        effects: const [Effect('english', 5)],
        source: 'preset',
      );

      expect(s.todayCount, 1, reason: '条数确实没变');
      expect(s.commentStale, true,
          reason: '条数一样但内容不同，必须重新生成');
    });

    test('指纹区分不同的记录组合', () async {
      final s = mkStore();
      await s.applyEffects(
          label: 'A', emoji: 'A', effects: const [Effect('english', 1)]);
      final f1 = s.todayFingerprint;
      await s.applyEffects(
          label: 'B', emoji: 'B', effects: const [Effect('english', 1)]);
      final f2 = s.todayFingerprint;
      expect(f1 == f2, false);
    });
  });

  group('状态型属性写入时的钳制', () {
    test('不会超过 100', () async {
      final s = mkStore();
      await s.applyEffects(
        label: '洗澡',
        emoji: '🚿',
        effects: const [Effect('mood', 999)],
      );
      expect(s.attr('mood')!.value, 100);
    });

    test('不会低于 0', () async {
      final s = mkStore();
      await s.applyEffects(
        label: '熬夜',
        emoji: '🦉',
        effects: const [Effect('mood', -999)],
      );
      expect(s.attr('mood')!.value, 0);
    });

    test('状态型从 60 加分不会溢出到等级语义', () async {
      final s = mkStore();
      await s.applyEffects(
        label: '洗澡',
        emoji: '🚿',
        effects: const [Effect('mood', 15)],
      );
      final a = s.attr('mood')!;
      expect(a.isState, true);
      expect(a.value, 75);
      expect(a.stateLabel, '良好');
    });

    test('能力型不受 100 上限约束', () async {
      final s = mkStore();
      await s.applyEffects(
        label: '猛学',
        emoji: '📚',
        effects: const [Effect('english', 350)],
      );
      final a = s.attr('english')!;
      expect(a.exp, 350);
      expect(a.level, 4);
    });
  });

  group('撤销能回滚', () {
    test('撤销后数值恢复', () async {
      final s = mkStore();
      final e = await s.applyEffects(
        label: '洗澡',
        emoji: '🚿',
        effects: const [Effect('mood', 15)],
      );
      expect(s.attr('mood')!.value, 75);
      await s.undo(e!);
      expect(s.attr('mood')!.value, 60);
      expect(s.logs.length, 0);
    });
  });
}
