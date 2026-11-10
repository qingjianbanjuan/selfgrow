import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 每日评语
class DailyComment {
  final String headline;
  final String body;
  final List<String> highlights;

  /// 今天值得肯定的
  final String? praise;

  /// 今天值得反省的
  final String? reflect;

  DailyComment(
    this.headline,
    this.body,
    this.highlights, {
    this.praise,
    this.reflect,
  });
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
              'max_tokens': 1600,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(_timeout);

      if (resp.statusCode != 200) {
        // 不要再静默失败：把状态码和响应体打出来
        final body = utf8.decode(resp.bodyBytes);
        debugPrint('[selfgrow] ai HTTP ${resp.statusCode} -> '
            '${body.length > 400 ? body.substring(0, 400) : body}');
        return null;
      }

      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final content =
          (j['choices'] as List).first['message']['content'] as String;
      final stripped = _stripFence(content);
      debugPrint('[selfgrow] ai raw content (${stripped.length} chars): '
          '${stripped.length > 300 ? stripped.substring(0, 300) : stripped}');
      return stripped;
    } catch (e) {
      debugPrint('[selfgrow] ai exception: $e');
      return null;
    }
  }

  /// 宽松解析：模型偶尔会输出带尾巴/前言的非标 JSON。
  /// 先直接解，失败就截取最外层 { } 再解。
  static Map<String, dynamic>? _parseLoose(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    final i = s.indexOf('{');
    final j = s.lastIndexOf('}');
    if (i >= 0 && j > i) {
      try {
        final v = jsonDecode(s.substring(i, j + 1));
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
    }
    return null;
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

  /// [worth_recording] 为 false 时仍然保留 effects（用户已明确要记录）
  /// [duration] 这件事持续了多久；未知时由 AI 自己估计
  static Future<AiJudgement?> judge({
    required String text,
    required List<Attribute> attrs,
    required List<AttrGroup> groups,
    List<AppUsageBrief> usage = const [],
    String? weather,
    DateTime? now,
    Duration? duration,
  }) async {
    final table = renderAttrTable(attrs, groups);

    final usageLine = usage.isEmpty
        ? '（无）'
        : usage.take(8).map((u) => u.label).join('、');

    String durText;
    if (duration != null && duration.inMinutes > 0) {
      durText = duration.inHours > 0
          ? '${duration.inHours} 小时 ${duration.inMinutes % 60} 分'
          : '${duration.inMinutes} 分钟';
    } else {
      durText = '未知 —— 你要自己估计一个合理时长';
    }

    final system = '''
你是「现实生活 → 属性数值」的翻译器。把用户描述的真实经历，翻译成对现有属性的数值增减。
你不评价、不建议、不鼓励，只做翻译。

【当前属性表】（effects 里的 attr 必须严格使用这里出现的中文名）
$table

【今天天气】${weather ?? '（未知）'}
【手机使用】$usageLine
【时间】${now ?? DateTime.now()}
【这件事持续了多久】$durText

规则：
1. 只输出 JSON，不要任何解释文字
2. effects[].attr 必须严格取自上面属性表，用中文名；匹配不上的不要硬塞
3. **影响幅度必须按「事件性质 × 持续时长」自己算**，不要给固定值。
   同样一件事，10 分钟和 5 小时的影响差别很大。参考量级：
   - 专注 / 意志 / 心情 这类状态：约 ±1~3 每小时（刷视频这类被动消耗更低，深度学习更高）
   - 体力 / 卫生：约 ±2~12 每小时（运动消耗大，睡觉恢复大）
   - 能力型（英语/编程/阅读…）：约 +3~10 每小时，且**只加在真的在练的那项上**
4. delta 整数，范围 -40 到 +40；超过 3 小时的事件可以更大
5. 一次事件影响 1-6 个属性，不要把所有属性都列上
6. 负面后果必须如实输出：运动后卫生下降、熬夜后体力下降、久坐后体力下降、
   长时间打游戏后专注和体力下降但心情上升等
7. 若事件涉及某个重要方面但属性表里完全没有对应，放进 suggest_attrs（最多 2 个）
8. summary ≤ 15 字；emoji 一个字符
9. worth_recording：只标记这件事是否琐碎，**不影响 effects 的计算**
10. 输出 duration_minutes：你实际采用的事件时长（整数分钟）

输出格式：
{"summary":"跑步30分钟","emoji":"🏃","duration_minutes":30,"worth_recording":true,
 "effects":[{"attr":"体力","delta":8},{"attr":"卫生","delta":-8}],
 "suggest_attrs":[{"name":"卫生","group":"身体","emoji":"🧼","init_exp":10}]}
''';

    final content = await _chat(system, text);
    if (content == null) return offlineJudge(text, attrs);

    try {
      final j = _parseLoose(content);
      if (j == null) {
        debugPrint('[selfgrow] judge: JSON 非法，走离线规则');
        return offlineJudge(text, attrs);
      }
      // 注意：AI 判断"不值得记"(worth_recording=false) 时**仍然保留 effects**。
      // 用户已经明确要记录，不该替他丢掉 —— 否则会以为记上了、其实没记。
      final worth = j['worth_recording'];
      if (worth is bool && !worth) {
        debugPrint('[selfgrow] judge: worth_recording=false，但仍保留 '
            '${(j['effects'] as List? ?? []).length} 条变化');
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
      final durMin = (j['duration_minutes'] as num?)?.toInt();
      final effDur = duration ??
          ((durMin != null && durMin > 0)
              ? Duration(minutes: durMin)
              : null);
      return AiJudgement(
        effects: effects,
        summary: (j['summary'] ?? text).toString(),
        emoji: (j['emoji'] ?? '🤖').toString(),
        suggestions: sugg,
        duration: effDur,
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
你在给这个人写一天的「每日评语」。你了解他的全部数据，可以有自己的判断和态度。
写给深夜的他看，要**像朋友说实话**，不像客服发通知。

【今天的时间线与属性变化】
$logsText

【当前属性与等级】
$table

【今天天气】${weather ?? '（未知）'}
【手机使用】$usageLine

怎么写：
1. headline：≤ 14 字，一句话定性，要有观点（可以犀利、可以惋惜、可以替他高兴）
2. body：**180 ~ 320 字**，这是主体。要写清：
   - 今天实际发生了什么（挑最有代表性的两三件，用具体数字和时间）
   - 这些事让他哪些属性涨了、哪些掉了，掉了多少
   - 你对他这一天的真实看法 —— 好在哪、差在哪
   **宁可具体到有点扎心，也不要空洞的漂亮话**
3. praise：1~2 句，今天真正值得肯定的地方。必须对应到具体事实，没有就留空字符串
4. reflect：1~2 句，今天值得反省的地方。可以说得直白、可以点破他自己在回避的事，
   但**不要说教**（不许出现"你应该""建议你""要加油"）
5. highlights：3~5 条，纯事实 + 数字，给别人一眼看懂今天什么样
6. 激励不靠口号。让"具体的事实 + 你的态度"本身起作用
   —— 比如"这周你第一次连续三天碰书"，比"继续努力"有力一百倍
7. **不许编造**：所有判断都必须能对应到上面的数据，没记录的事不许猜
8. 可以主观，可以有情绪，可以调侃，但**不能伤人**
9. 只输出 JSON

输出格式：
{"headline":"身体动了，脑子没动",
 "body":"今天你跑了 30 分钟，体力从 62 拉到 71，这是这两天最有价值的一段时间。但一整天没翻开过书，阅读停在 Lv1 已经第 9 天了。晚上 11 点后还在刷视频，专注又掉了 4 点。你不是没时间，是把时间都给了屏幕。",
 "praise":"跑步那一趟是真的，热天能出门不容易。",
 "reflect":"连续 9 天没读书了。你自己也知道这不对劲。",
 "highlights":["运动 32 分钟","阅读 0 分钟","屏幕 7.0 小时","专注 -8"]}
''';

    final content = await _chat(system, '请写今天的评语。');
    if (content == null) return null;
    try {
      final j = _parseLoose(content);
      if (j == null) {
        debugPrint('[selfgrow] dailyComment: JSON 非法');
        return null;
      }
      final h = (j['highlights'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      String? opt(String k) {
        final v = (j[k] ?? '').toString().trim();
        return v.isEmpty ? null : v;
      }

      return DailyComment(
        (j['headline'] ?? '').toString(),
        (j['body'] ?? '').toString(),
        h,
        praise: opt('praise'),
        reflect: opt('reflect'),
      );
    } catch (e) {
      debugPrint('[selfgrow] dailyComment JSON parse failed: $e');
      return null;
    }
  }
}
