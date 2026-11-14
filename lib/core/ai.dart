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

  /// 把使用记录分成「真的在用手机」和「背景播放」两段。
  /// 听歌/播客很可能是在边听边做事，不能算刷手机。
  static String renderUsage(List<AppUsageBrief> usage) {
    if (usage.isEmpty) return '（无）';
    final screen = usage.where((u) => !u.isBackground).toList();
    final bg = usage.where((u) => u.isBackground).toList();

    final parts = <String>[];
    if (screen.isNotEmpty) {
      parts.add(screen.take(12).map((u) => u.label).join('、'));
    }
    if (bg.isNotEmpty) {
      parts.add(
          '（背景播放，不算刷手机：${bg.take(4).map((u) => u.label).join('、')}）');
    }
    return parts.isEmpty ? '（无）' : parts.join(' ');
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

    final usageLine = renderUsage(usage);

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
8. summary ≤ 15 字；emoji 一个字符。
   **summary 里不许出现任何时长数字**（不许"刷手机12小时"这种），
   只说做了什么（"刷手机"/"学英语"/"跑步"）。时长由界面另外显示。
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

  /// "7 小时 38 分" / "45 分钟"
  static String _durText(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m 分钟';
    return m > 0 ? '$h 小时 $m 分' : '$h 小时';
  }

  /// 把一个时长登记进「可引用数字」白名单
  static void _allowDuration(Set<String> allow, Duration d) {
    final total = d.inMinutes;
    allow.add('$total'); // 分钟总数
    allow.add('${d.inHours}'); // 小时部分
    allow.add('${d.inMinutes % 60}'); // 分钟部分
    final dec = total / 60.0;
    allow.add(dec.toStringAsFixed(1)); // 7.6
    allow.add(dec.toStringAsFixed(0)); // 8
  }


  static final _durRe = RegExp(r'(\d+(?:\.\d+)?)\s*(?:小时|分钟|分|h|min)');
  static final _timeRe = RegExp(r'(\d{1,2}):(\d{2})');

  /// 这段文本里的「X 小时 / X 分钟 / HH:MM」是不是都在白名单里。
  ///
  /// 关键：**时长必须来自真实时长集合**（durAllow），
  /// 不能因为某个属性的增减恰好是 12，就放行"12 小时"。
  static bool _grounded(
      String text, Set<String> durAllow, Set<String> timeAllow) {
    for (final m in _durRe.allMatches(text)) {
      if (!durAllow.contains(m.group(1)!)) return false;
    }
    for (final m in _timeRe.allMatches(text)) {
      final hh = int.tryParse(m.group(1)!) ?? -1;
      final mm = m.group(2)!;
      if (hh < 0 || hh > 23) continue; // 不是时间，跳过
      final key = '${hh.toString().padLeft(2, '0')}:$mm';
      final key2 = '$hh:$mm';
      if (!timeAllow.contains(key) && !timeAllow.contains(key2)) {
        return false;
      }
    }
    return true;
  }

  /// 把含未授权数字的句子剔掉（按句切断，保留符号）
  static String _scrub(
      String text, Set<String> durAllow, Set<String> timeAllow) {
    if (text.isEmpty) return text;
    final out = <String>[];
    final buf = StringBuffer();
    for (final ch in text.split('')) {
      buf.write(ch);
      if ('。！？；\n'.contains(ch)) {
        final s = buf.toString();
        if (_grounded(s, durAllow, timeAllow)) out.add(s);
        buf.clear();
      }
    }
    final tail = buf.toString();
    if (tail.trim().isNotEmpty &&
        _grounded(tail, durAllow, timeAllow)) {
      out.add(tail);
    }
    return out.join().trim();
  }

  static Future<DailyComment?> dailyComment({
    required List<LogEntry> todayLogs,
    required List<Attribute> attrs,
    required List<AttrGroup> groups,
    String? weather,
    List<AppUsageBrief> usage = const [],
    String? sleepInfo,
    Duration? sleepDuration,
    Duration? totalScreen,
  }) async {
    if (!AiConfig.hasKey) return null;

    final table = renderAttrTable(attrs, groups);

    // ---------- 1. 白名单：时长 和 时间点 分开收集 ----------
    // 关键：时长只能来自真实时长，绝不能因为某个属性增减恰好是 12
    // 就放行"12 小时"（之前就是这么漏的）
    final durAllow = <String>{}; // 真实时长
    final timeAllow = <String>{}; // 真实时间点

    final logsText = todayLogs.isEmpty
        ? '（今天还没有任何记录）'
        : todayLogs
            .take(40)
            .map((l) {
              final t =
                  '${l.time.hour.toString().padLeft(2, '0')}:${l.time.minute.toString().padLeft(2, '0')}';
              timeAllow.add(t);
              final eff = l.effects.map((e) {
                final a = attrs.where((x) => x.id == e.attrId).toList();
                final n = a.isEmpty ? e.attrId : a.first.name;
                return '$n${e.delta >= 0 ? '+' : ''}${e.delta}';
              }).join(' ');
              return '$t ${l.label} ｜ $eff';
            })
            .join('\n');

    // 属性今日累计变化（AI 引用"专注-14"是允许的 —— 那是真实求和）
    final sums = <String, int>{};
    for (final l in todayLogs) {
      for (final e in l.effects) {
        sums[e.attrId] = (sums[e.attrId] ?? 0) + e.delta;
      }
    }

    // 屏幕总时长
    if (totalScreen != null) _allowDuration(durAllow, totalScreen);

    // 各 App
    final appFacts = <String>[];
    for (final u in usage.take(12)) {
      _allowDuration(durAllow, u.duration);
      appFacts.add('${u.appName} ${_durText(u.duration)}');
    }

    // 睡眠时长
    if (sleepDuration != null) _allowDuration(durAllow, sleepDuration);

    // ---------- 2. 事实清单，明确给 AI ----------
    final facts = <String>[
      if (totalScreen != null)
        '今天屏幕总时长 ${_durText(totalScreen)}（${totalScreen.inMinutes} 分钟）',
      if (sleepInfo != null) '昨晚睡眠 $sleepInfo',
      '今天记录 ${todayLogs.length} 条',
      if (appFacts.isNotEmpty) '各 App：${appFacts.join('、')}',
      if (sums.isNotEmpty)
        '今日属性累计：${sums.entries.map((e) {
          final n = attrs.where((a) => a.id == e.key);
          return '${n.isEmpty ? e.key : n.first.name}${e.value >= 0 ? '+' : ''}${e.value}';
        }).join('、')}',
    ].join('\n');

    final usageLine = renderUsage(usage);

    final system = '''
你在给这个人写一天的「每日评语」。你了解他的全部数据，可以有自己的判断和态度。
写给深夜的他看，要像朋友说实话，不像客服发通知。

【今天的时间线与属性变化】
$logsText

【当前属性与等级】
$table

【真实数据（唯一允许引用的数字）】
$facts
【昨晚睡眠】${sleepInfo ?? '（没检测到）'}
【今天天气】${weather ?? '（未知）'}
【手机使用】$usageLine

**最硬的规矩：数字只能从上表抄，一个都不许自己算、不许估、不许编。**
- 不许多报时长（比如表里没有"12 小时"这种数，就绝对不许写）
- 不许把"刷了几次"换算成"刷了几小时"
- 拿不准就不写数字，只描述趋势
- 编造数字是最严重的错误，比写得不精彩严重一百倍

怎么写：
1. headline：≤ 14 字，一句话定性，要有观点
2. body：**180 ~ 320 字**。写清今天实际发生了什么（用上面的真实数字和时间）、
   属性怎么涨跌、你对他这一天的真实看法。**宁可具体到扎心，也不要空洞的漂亮话**
3. praise：1~2 句，今天真正值得肯定的地方，必须有依据，没有就留空字符串
4. reflect：1~2 句，值得反省的地方，可以直白，但不要说教
   （不许出现"你应该""建议你""要加油"）
5. highlights：3~5 条，纯事实 + 数字，**数字同样只能来自上表**
6. 激励不靠口号，靠"具体的事实 + 你的态度"
7. 可以主观，可以有情绪，可以调侃，但**不能伤人**
8. 只输出 JSON

输出格式：
{"headline":"一句话定性",
 "body":"180-320 字的评语",
 "praise":"值得肯定的",
 "reflect":"值得反省的",
 "highlights":["事实1","事实2","事实3"]}
''';

    // ---------- 3. 生成 + 校验 + 重试 ----------
    DailyComment? build(Map<String, dynamic> j) {
      String? opt(String k) {
        final v = (j[k] ?? '').toString().trim();
        return v.isEmpty ? null : v;
      }

      final body = _scrub((j['body'] ?? '').toString(), durAllow, timeAllow);
      // 剔完太短 = 大部分内容都是编的，判失败
      if (body.length < 40 && (j['body'] ?? '').toString().length > 60) {
        debugPrint('[selfgrow] dailyComment: 正文被剔空，判为幻觉');
        return null;
      }

      final hs = (j['highlights'] as List? ?? [])
          .map((e) => e.toString())
          .where((s) => _grounded(s, durAllow, timeAllow))
          .toList();

      return DailyComment(
        (j['headline'] ?? '').toString(),
        body,
        hs,
        praise: opt('praise') == null
            ? null
            : _scrub(opt('praise')!, durAllow, timeAllow),
        reflect: opt('reflect') == null
            ? null
            : _scrub(opt('reflect')!, durAllow, timeAllow),
      );
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final sys = attempt == 0
          ? system
          : '$system\n\n【上一次的回答里出现了表里没有的数字，这是严重错误。'
              '这一次请只用【真实数据】里出现过的数字。】';
      final content = await _chat(sys, '请写今天的评语。');
      if (content == null) continue;
      final j = _parseLoose(content);
      if (j == null) {
        debugPrint('[selfgrow] dailyComment: JSON 非法（第 ${attempt + 1} 次）');
        continue;
      }
      final c = build(j);
      if (c != null && c.body.trim().length >= 40) {
        debugPrint('[selfgrow] dailyComment OK（第 ${attempt + 1} 次）');
        return c;
      }
    }

    // ---------- 4. 兜底：本地按事实拼，绝不含编造数字 ----------
    debugPrint('[selfgrow] dailyComment: 两次都不可信，用本地事实拼');
    return _localComment(todayLogs, attrs, usage, sleepInfo, totalScreen);
  }

  /// 完全由本地数据拼出来的评语（没有 AI 发挥，因此不可能编造）
  static DailyComment _localComment(
    List<LogEntry> logs,
    List<Attribute> attrs,
    List<AppUsageBrief> usage,
    String? sleepInfo,
    Duration? totalScreen,
  ) {
    final sums = <String, int>{};
    final names = <String, String>{};
    for (final l in logs) {
      for (final e in l.effects) {
        sums[e.attrId] = (sums[e.attrId] ?? 0) + e.delta;
        final a = attrs.where((x) => x.id == e.attrId);
        if (a.isNotEmpty) names[e.attrId] = a.first.name;
      }
    }

    final sb = StringBuffer();
    if (totalScreen != null) {
      sb.write('今天屏幕时长 ${_durText(totalScreen)}。');
    }
    sb.write('记录了 ${logs.length} 条。');
    if (sleepInfo != null) sb.write('昨晚：$sleepInfo。');

    final parts = sums.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    if (parts.isNotEmpty) {
      sb.write('变化最大的：');
      sb.write(parts
          .take(4)
          .map((e) =>
              '${names[e.key] ?? e.key}${e.value >= 0 ? '+' : ''}${e.value}')
          .join('、'));
      sb.write('。');
    }
    if (usage.isNotEmpty) {
      sb.write('手机主要用在 ${usage.first.appName}（${_durText(usage.first.duration)}）。');
    }

    final hs = <String>[
      if (totalScreen != null) '屏幕 ${_durText(totalScreen)}',
      '记录 ${logs.length} 条',
      if (sleepInfo != null) '睡眠 $sleepInfo',
      ...parts.take(2).map((e) =>
          '${names[e.key] ?? e.key}${e.value >= 0 ? '+' : ''}${e.value}'),
    ];

    return DailyComment(
      '今天的账',
      sb.toString(),
      hs,
      reflect: null,
      praise: null,
    );
  }
}