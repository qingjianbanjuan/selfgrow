import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 每日评价结果
class DailyComment {
  final String headline;
  final String body;
  final List<String> highlights;
  DailyComment(this.headline, this.body, this.highlights);
}

/// AI 配置（Key 存在本地，不进代码库）
class AiConfig {
  static const _kKey = 'sg_ai_key';
  static const _kModel = 'sg_ai_model';

  static String apiKey = '';
  static String model = 'deepseek-chat';

  static bool get hasKey => apiKey.trim().isNotEmpty;

  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    apiKey = sp.getString(_kKey) ?? '';
    model = sp.getString(_kModel) ?? 'deepseek-chat';
  }

  static Future<void> setKey(String key) async {
    apiKey = key.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKey, apiKey);
  }

  static Future<void> setModel(String m) async {
    model = m.trim().isEmpty ? 'deepseek-chat' : m.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kModel, model);
  }
}

/// AI 判定服务
class AiService {
  static const _endpoint = 'https://api.deepseek.com/chat/completions';
  static const _timeout = Duration(seconds: 30);

  // ---------------- 通用请求 ----------------

  static Future<String?> _chat(String system, String user) async {
    if (!AiConfig.hasKey) return null;
    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${AiConfig.apiKey}',
            },
            body: jsonEncode({
              'model': AiConfig.model,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
              'temperature': 0.3,
              'max_tokens': 1200,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final content =
          (j['choices'] as List).first['message']['content'] as String;
      return _stripFence(content);
    } catch (_) {
      return null;
    }
  }

  static String _stripFence(String s) {
    var t = s.trim();
    if (t.startsWith('```')) {
      final i = t.indexOf('\n');
      if (i > 0) t = t.substring(i + 1);
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    }
    return t.trim();
  }

  // ---------------- 属性表渲染 ----------------

  static String renderAttrTable(
      List<Attribute> attrs, List<AttrGroup> groups) {
    final sb = StringBuffer();
    final sorted = groups.toList()..sort((a, b) => a.order.compareTo(b.order));
    for (final g in sorted) {
      final list = attrs
          .where((a) => a.groupId == g.id && a.enabled)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (list.isEmpty) continue;
      sb.write('${g.name}：');
      sb.writeln(list.map((a) => '${a.name}(Lv${a.level})').join(' '));
    }
    return sb.toString().trim();
  }

  static Attribute? _matchAttr(List<Attribute> attrs, String raw) {
    final name = raw.trim();
    if (name.isEmpty) return null;
    // 1. 完全匹配
    for (final a in attrs) {
      if (a.name == name) return a;
    }
    // 2. 去掉括号/等级后缀再匹配
    final clean = name.replaceAll(RegExp(r'[（(].*?[)）]'), '').trim();
    for (final a in attrs) {
      if (a.name == clean) return a;
    }
    // 3. 包含匹配
    for (final a in attrs) {
      if (a.name.contains(clean) || clean.contains(a.name)) return a;
    }
    return null;
  }

  // ---------------- 事件判定 ----------------

  /// [worth_recording] 为 false 时不建议记录
  static Future<AiJudgement?> judge({
    required String text,
    required List<Attribute> attrs,
    required List<AttrGroup> groups,
    List<AppUsageBrief> usage = const [],
    String? weather,
    DateTime? now,
  }) async {
    final table = renderAttrTable(attrs, groups);
    final usable = attrs.where((a) => a.enabled).map((a) => a.name).join('、');

    final usageLine = usage.isEmpty
        ? '（无）'
        : usage.take(8).map((u) => u.label).join('、');

    final system = '''
你是「现实生活 → 属性数值」的翻译器。把用户描述的真实经历，翻译成对现有属性的数值增减。
你不评价、不建议、不鼓励，只做翻译。

【当前属性表】（effects 里的 attr 必须严格使用这里出现的中文名）
$table

【今天天气】${weather ?? '（未知）'}

【时间】${now ?? DateTime.now()}

规则：
1. 只输出 JSON，不要任何解释文字
2. effects[].attr 必须严格取自上面属性表，用中文名；匹配不上的不要硬塞
3. delta 是整数，范围 -30 到 +30
4. 一次事件影响 1-5 个属性，不要把所有属性都列上
5. 负面后果必须如实输出：运动后卫生下降、熬夜后体力下降、久坐后体力下降等
6. 若事件涉及某个重要方面但属性表里完全没有对应，放进 suggest_attrs（最多 2 个）
7. summary ≤ 15 字；emoji 一个字符
8. worth_recording：这件事是否值得进时间轴。琐碎到（"刷了 5 分钟手机"）填 false

输出格式：
{"summary":"跑步30分钟","emoji":"🏃","worth_recording":true,
 "effects":[{"attr":"体力","delta":8},{"attr":"卫生","delta":-8}],
 "suggest_attrs":[{"name":"卫生","group":"身体","emoji":"🧼","init_exp":10}]}
''';

    final content = await _chat(system, text);
    if (content == null) return offlineJudge(text, attrs);

    try {
      final j = jsonDecode(content) as Map<String, dynamic>;
      final worth = j['worth_recording'];
      if (worth is bool && !worth) {
        return AiJudgement(
          effects: const [],
          summary: (j['summary'] ?? '').toString(),
          emoji: (j['emoji'] ?? '•').toString(),
          reasoning: 'worth_recording=false',
        );
      }
      final effects = <Effect>[];
      for (final e in (j['effects'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(e as Map);
        final a = _matchAttr(attrs, (m['attr'] ?? '').toString());
        if (a == null) continue;
        final d = (m['delta'] as num?)?.toInt() ?? 0;
        if (d == 0) continue;
        effects.add(Effect(a.id, d));
      }
      final sugg = <SuggestedAttr>[];
      for (final s in (j['suggest_attrs'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(s as Map);
        final n = (m['name'] ?? '').toString().trim();
        if (n.isEmpty) continue;
        // 已存在同名属性就跳过
        if (attrs.any((a) => a.name == n)) continue;
        sugg.add(SuggestedAttr.fromJson(m));
      }
      return AiJudgement(
        effects: effects,
        summary: (j['summary'] ?? text).toString(),
        emoji: (j['emoji'] ?? '🤖').toString(),
        suggestions: sugg,
      );
    } catch (_) {
      return offlineJudge(text, attrs);
    }
  }

  // ---------------- 离线兜底 ----------------

  /// 关键词规则：没网 / 没填 Key 时用
  static const Map<String, List<(String, int)>> _rules = {
    '跑步': [('体力', 8), ('健康', 5), ('耐力', 6), ('卫生', -8)],
    '跑了': [('体力', 8), ('健康', 5), ('耐力', 6), ('卫生', -8)],
    '走路': [('体力', 3), ('健康', 2)],
    '散步': [('体力', 3), ('健康', 3), ('心情', 2)],
    '健身': [('力量', 8), ('体力', 5), ('卫生', -6)],
    '力量训练': [('力量', 9), ('体力', 4), ('卫生', -6)],
    '洗澡': [('卫生', 15), ('心情', 4), ('体力', 2)],
    '淋浴': [('卫生', 15), ('心情', 4)],
    '洗头': [('卫生', 8)],
    '刷牙': [('卫生', 3)],
    '读书': [('阅读', 8), ('智力', 4), ('专注', 5), ('学习', 5)],
    '看书': [('阅读', 8), ('智力', 4), ('专注', 5)],
    '学英语': [('英语', 7), ('记忆', 2), ('学习', 3)],
    '背单词': [('英语', 6), ('记忆', 4)],
    '英语': [('英语', 5)],
    '写代码': [('编程', 7), ('逻辑', 4), ('专注', 4)],
    '编程': [('编程', 6), ('逻辑', 3)],
    '敲代码': [('编程', 7), ('逻辑', 4)],
    '写东西': [('写作', 6), ('表达', 4)],
    '写作': [('写作', 7), ('表达', 4)],
    '冥想': [('稳定', 6), ('抗压', 5), ('专注', 3), ('心情', 3)],
    '早睡': [('睡眠', 12), ('心情', 4), ('体力', 5), ('稳定', 3)],
    '熬夜': [('睡眠', -12), ('体力', -5), ('心情', -4), ('健康', -5)],
    '失眠': [('睡眠', -10), ('心情', -4)],
    '吃饭': [('饮食', 8), ('体力', 3)],
    '好好吃饭': [('饮食', 8), ('体力', 3)],
    '做饭': [('饮食', 6), ('动手', 5), ('心情', 3)],
    '整理': [('秩序', 7), ('自律', 4), ('心情', 2)],
    '打扫': [('秩序', 7), ('卫生', 5), ('体力', 3)],
    '记账': [('财务', 6), ('秩序', 4), ('自律', 3)],
    '和朋友': [('亲和', 6), ('沟通', 4), ('心情', 5)],
    '聚会': [('亲和', 6), ('沟通', 4), ('心情', 5)],
    '聊天': [('沟通', 4), ('亲和', 3)],
    '吵架': [('心情', -6), ('稳定', -4), ('沟通', -3)],
    '刷手机': [('专注', -4), ('意志', -3), ('心情', 1)],
    '刷视频': [('专注', -5), ('意志', -3)],
    '看视频': [('专注', -3)],
    '游戏': [('专注', -2), ('心情', 3)],
    '打游戏': [('心情', 4), ('专注', -3)],
    '画画': [('创造', 6), ('审美', 5), ('心情', 3)],
    '创作': [('创造', 7), ('审美', 4)],
    '设计': [('设计', 6), ('审美', 5), ('创造', 3)],
    '上课': [('学习', 5), ('专注', 4)],
    '开会': [('沟通', 4), ('专业', 3)],
    '加班': [('专业', 5), ('体力', -5), ('睡眠', -3), ('心情', -3)],
    '写作业': [('学习', 5), ('自律', 3)],
  };

  static AiJudgement offlineJudge(String text, List<Attribute> attrs) {
    final acc = <String, int>{};
    for (final entry in _rules.entries) {
      if (text.contains(entry.key)) {
        for (final (name, delta) in entry.value) {
          final a = _matchAttr(attrs, name);
          if (a == null) continue;
          acc[a.id] = (acc[a.id] ?? 0) + delta;
        }
      }
    }
    final effects = acc.entries
        .where((e) => e.value != 0)
        .map((e) => Effect(e.key, e.value))
        .toList();
    return AiJudgement(
      effects: effects,
      summary: text.length > 15 ? '${text.substring(0, 15)}…' : text,
      emoji: '📝',
      reasoning: '离线关键词规则',
    );
  }

  // ---------------- 每日评价 ----------------

  static Future<DailyComment?> dailyComment({
    required List<LogEntry> todayLogs,
    required List<Attribute> attrs,
    required List<AttrGroup> groups,
    String? weather,
    List<AppUsageBrief> usage = const [],
  }) async {
    if (!AiConfig.hasKey) return null;

    final table = renderAttrTable(attrs, groups);

    final logsText = todayLogs.isEmpty
        ? '（今天还没有任何记录）'
        : todayLogs
            .take(40)
            .map((l) {
              final t =
                  '${l.time.hour.toString().padLeft(2, '0')}:${l.time.minute.toString().padLeft(2, '0')}';
              final eff = l.effects.map((e) {
                final a = attrs.where((x) => x.id == e.attrId).toList();
                final n = a.isEmpty ? e.attrId : a.first.name;
                return '$n${e.delta >= 0 ? '+' : ''}${e.delta}';
              }).join(' ');
              return '$t ${l.label} ｜ $eff';
            })
            .join('\n');

    final usageLine = usage.isEmpty
        ? '（无）'
        : usage.take(8).map((u) => u.label).join('、');

    final system = '''
你在写一份「今日状态陈述」。你是一面镜子，不是教练。

【今天的时间线与属性变化】
$logsText

【当前属性与等级】
$table

【今天天气】${weather ?? '（未知）'}
【手机使用】$usageLine

规则：
1. headline ≤ 12 字，概括今天的重心
2. body ≤ 120 字，陈述今天发生了什么、属性怎么变，可以提到具体数字
3. highlights 3-5 条，每条是「事实 + 数字」
4. 严禁：祈使句、建议、鼓励口号、好坏评价、因果推断（如"因为懒所以没运动"）
5. 允许：具体数字、时间线、平淡的观察、一点点温度
6. 只输出 JSON

输出格式：
{"headline":"身体动了，脑子没动","body":"今天跑步 30 分钟，体力涨了一级多。一整天没有阅读记录。","highlights":["运动 32 分钟","阅读 0 分钟","屏幕 4.2 小时"]}
''';

    final content = await _chat(system, '请生成今天的陈述。');
    if (content == null) return null;
    try {
      final j = jsonDecode(content) as Map<String, dynamic>;
      final h = (j['highlights'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      return DailyComment(
        (j['headline'] ?? '').toString(),
        (j['body'] ?? '').toString(),
        h,
      );
    } catch (_) {
      return null;
    }
  }
}
