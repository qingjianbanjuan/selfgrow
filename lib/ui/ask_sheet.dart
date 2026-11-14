import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/usage.dart';
import 'theme.dart';

/// 打开 App 时的处理面板。
///
/// 原则：**能自己判断的就不问**。
/// - 有明确的前台应用 → 直接让 AI 判定并记上，只把结果摆出来
/// - **只在听歌（没碰别的 App）** → 听歌说明不了在干什么，这时候才问
/// - 手机之外的时间（睡觉/吃饭/上课）→ 它不知道，问
Future<void> showAskSheet(
  BuildContext context,
  GameStore store, {
  required DateTime since,
  required List<AppUsageBrief> usage,
  required bool hasUsagePermission,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _AskSheet(
      store: store,
      since: since,
      usage: usage,
      hasUsagePermission: hasUsagePermission,
    ),
  );
}

class _AskSheet extends StatefulWidget {
  final GameStore store;
  final DateTime since;
  final List<AppUsageBrief> usage;
  final bool hasUsagePermission;

  const _AskSheet({
    required this.store,
    required this.since,
    required this.usage,
    required this.hasUsagePermission,
  });

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _ctrl = TextEditingController();

  AiJudgement? _usageJudge;
  bool _judging = false;
  bool _working = false;
  String? _error;

  /// 自动推断出来的昨晚睡眠
  SleepVerdict? _sleep;

  @override
  void initState() {
    super.initState();
    // 只有"有明确前台应用"时才自动判定；纯听歌判定不了，要等人回答
    if (!_musicOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _judgeUsage());
    }
    // 睡眠和前台应用无关，总是自己试一下
    WidgetsBinding.instance.addPostFrameCallback((_) => _detectSleep());
  }

  /// 只推断「昨晚」的睡眠：从昨天 18:00 到现在
  /// （午睡之类用户会自己说，不用猜）
  Future<void> _detectSleep() async {
    if (!await UsageService.hasPermission()) return;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final span = await UsageService.detectSleep(
      since: todayStart.subtract(const Duration(hours: 6)), // 昨天 18:00
      until: now,
      // 只认跨过今天凌晨 4 点的那段，白天上班的长空白不算
      mustContain: GameStore.sleepAnchor(),
    );
    if (span == null) return;
    if (!widget.store.shouldRecordSleepEnd(span.to)) return;
    if (!mounted) return;
    setState(() => _sleep = UsageService.judgeSleep(span));
  }

  /// 睡眠属性的 id（用户可能改过名）
  String? get _sleepAttrId {
    for (final a in widget.store.attrs) {
      if (a.id == 'sleep' || a.name == '睡眠') return a.id;
    }
    return null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Duration get _gap => DateTime.now().difference(widget.since);

  /// 非背景的应用（真的在"用手机"）
  List<AppUsageBrief> get _screenApps =>
      widget.usage.where((u) => !u.isBackground).toList();

  /// 听歌类（背景播放）
  List<AppUsageBrief> get _musicApps =>
      widget.usage.where((u) => u.isBackground).toList();

  /// 只听了歌，没碰别的 App
  bool get _musicOnly => _screenApps.isEmpty && _musicApps.isNotEmpty;

  Duration _sum(List<AppUsageBrief> list) {
    var ms = 0;
    for (final u in list) {
      ms += u.duration.inMilliseconds;
    }
    return Duration(milliseconds: ms);
  }

  Duration get _screenTotal => _sum(_screenApps);
  Duration get _musicTotal => _sum(_musicApps);

  /// 手机外的时间 = 总窗口 - 手机上真正在用的时间
  Duration get _offPhoneGap {
    final d = _gap - _screenTotal - _musicTotal;
    return d.isNegative ? Duration.zero : d;
  }

  String get _musicName => _musicApps.isEmpty ? '音乐' : _musicApps.first.appName;

  String get _sinceText =>
      '${widget.since.hour.toString().padLeft(2, '0')}:${widget.since.minute.toString().padLeft(2, '0')}';

  String _fmt(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m > 0 ? '$h 小时 $m 分' : '$h 小时';
  }

  /// 给 AI 的描述文本
  String get _usageText {
    final parts = <String>[];
    if (_screenApps.isNotEmpty) {
      parts.add('手机使用：${_screenApps.map((u) => u.label).join('、')}');
    }
    if (_musicApps.isNotEmpty) {
      parts.add('同时背景播放：${_musicApps.map((u) => u.label).join('、')}'
          '（边听边做事，不算刷手机）');
    }
    return parts.isEmpty ? '这段时间没有手机使用记录' : parts.join('；');
  }

  /// 自动判定有明确前台应用的那段
  Future<void> _judgeUsage() async {
    if (_screenApps.isEmpty) return;
    setState(() {
      _judging = true;
      _error = null;
    });
    final j = await AiService.judge(
      text: _usageText,
      attrs: widget.store.attrs,
      groups: widget.store.groups,
      duration: _gap,
    );
    if (!mounted) return;
    setState(() {
      _judging = false;
      _usageJudge = j;
      if (j == null) _error = '判定失败（网络或 Key 有问题）';
    });
  }

  Future<void> _apply(AiJudgement j, String? rawText) async {
    if (j.effects.isEmpty) return;
    await widget.store.applyEffects(
      label: j.summary,
      emoji: j.emoji,
      effects: j.effects,
      source: 'ai',
      rawText: rawText,
      summary: j.summary,
    );
  }

  /// 主操作
  Future<void> _commit() async {
    if (_working) return;

    final typed = _ctrl.text.trim();

    // 纯听歌场景：必须知道在干什么，否则记了也没意义
    if (_musicOnly && typed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('选一个，或者说一句你在干嘛'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _working = true);
    var count = 0;

    // 0) 昨晚的睡眠（自动推断的，不用人确认）
    final sv = _sleep;
    final sleepAttr = _sleepAttrId;
    if (sv != null && sleepAttr != null && sv.delta != 0) {
      await widget.store.applyEffects(
        label: '睡觉 ${sv.span.durationText}',
        emoji: '😴',
        effects: [Effect(sleepAttr, sv.delta)],
        source: 'auto',
        rawText: '自动推断：${sv.span.clockText}，${sv.reason}',
        summary: '昨晚睡了 ${sv.span.durationText}',
        time: sv.span.to,
      );
      await widget.store.markSleepRecorded(sv.span.from, sv.span.to);
      count++;
    }

    if (_musicOnly) {
      // 听歌 + 用户说的活动 → 一起交给 AI 判定
      final j = await AiService.judge(
        text: '边听 $_musicName（${_fmt(_musicTotal)}），$typed',
        attrs: widget.store.attrs,
        groups: widget.store.groups,
        duration: _gap,
      );
      if (j != null && j.effects.isNotEmpty) {
        await _apply(j, typed);
        count++;
      }
    } else {
      // 1) 有明确前台应用的自动判定
      final uj = _usageJudge;
      if (uj != null && uj.effects.isNotEmpty) {
        await _apply(uj, _usageText);
        count++;
      }
      // 2) 用户补充的（手机之外）
      if (typed.isNotEmpty) {
        final j = await AiService.judge(
          text: typed,
          attrs: widget.store.attrs,
          groups: widget.store.groups,
          duration: _offPhoneGap.inMinutes > 1 ? _offPhoneGap : null,
        );
        if (j != null && j.effects.isNotEmpty) {
          await _apply(j, typed);
          count++;
        }
      }
    }

    await widget.store.markAsked();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Text(
        count > 0 ? '已记下 $count 条（${_fmt(_gap)}）' : '这段时间没有产生属性变化',
        style: const TextStyle(fontSize: 13),
      ),
    ));
  }

  Future<void> _skip() async {
    await widget.store.markAsked();
    if (mounted) Navigator.pop(context);
  }

  /// 纯听歌时问：边听歌在干什么
  List<String> get _activityGuesses =>
      const ['在写代码', '在看书', '在通勤', '在打游戏', '在发呆', '在聊天'];

  /// 有前台应用时问：手机之外在干什么
  List<String> get _offPhoneGuesses =>
      const ['在睡觉', '在吃饭', '在上课', '在运动', '在外面逛'];

  @override
  Widget build(BuildContext context) {
    final hasUsage = widget.hasUsagePermission && widget.usage.isNotEmpty;
    final askOffPhone = !_musicOnly && (_offPhoneGap.inMinutes >= 15 || !hasUsage);
    final guesses = _musicOnly ? _activityGuesses : _offPhoneGuesses;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- 标题 ----------
              Text(
                '$_sinceText 之后到现在（${_fmt(_gap)}）',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                !widget.hasUsagePermission
                    ? '没授权使用情况，只能问你了'
                    : _musicOnly
                        ? '这段时间只开着 $_musicName，没碰别的 App'
                        : hasUsage
                            ? '手机上这段我自己判断，不用你说了'
                            : '这段时间手机上没查到记录',
                style: TextStyle(fontSize: 11, color: kSub.withAlpha(190)),
              ),
              const SizedBox(height: 14),

              // ---------- 昨晚睡眠（自动推断）----------
              if (_sleep != null) ...[
                _SleepBlock(verdict: _sleep!),
                const SizedBox(height: 10),
              ],

              // ---------- 使用情况 ----------
              if (!widget.hasUsagePermission) ...[
                _permHint(),
                const SizedBox(height: 14),
              ] else if (hasUsage) ...[
                if (_musicOnly)
                  _MusicOnlyBlock(music: _musicApps, total: _musicTotal)
                else
                  _UsageBlock(
                    screen: _screenApps,
                    music: _musicApps,
                    screenTotal: _screenTotal,
                    musicTotal: _musicTotal,
                    judge: _usageJudge,
                    judging: _judging,
                    attrs: widget.store.attrs,
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(fontSize: 11, color: kDown)),
                  ),
                const SizedBox(height: 14),
              ],

              // ---------- 询问 ----------
              if (_musicOnly || askOffPhone) ...[
                Text(
                  _musicOnly
                      ? '只是听歌判断不了在做什么，你在干嘛？'
                      : (hasUsage
                          ? '其余 ${_fmt(_offPhoneGap)} 没有手机记录，在干什么？（可不填）'
                          : '这段时间在干什么？'),
                  style: const TextStyle(fontSize: 12, color: kSub),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: guesses
                      .map((g) => InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () {
                              _ctrl.text = g;
                              _commit();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 9),
                              decoration: BoxDecoration(
                                color: kSurface2,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(g,
                                  style: const TextStyle(fontSize: 12.5)),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  maxLines: 2,
                  minLines: 1,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _musicOnly
                        ? '或者说一句，比如「边听歌边写了会儿代码」'
                        : '或者说一句，比如「在图书馆看了两小时书」',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ---------- 操作 ----------
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _working ? null : _skip,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kSub,
                        side: const BorderSide(color: kSurface2),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('跳过'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _working || _judging ? null : _commit,
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccent,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: _working
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              _musicOnly
                                  ? '记上'
                                  : (_usageJudge != null ? '就这样记' : '记上'),
                              style: const TextStyle(fontSize: 14),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permHint() {
    return InkWell(
      onTap: () => UsageService.openPermissionSettings(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kAccent.withAlpha(60)),
        ),
        child: const Row(
          children: [
            Icon(Icons.phonelink_setup, size: 16, color: kAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '允许读取「使用情况」，手机上做了什么我就能自己判断，不用问你',
                style: TextStyle(fontSize: 11.5, color: kSub),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: kSub),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 共用

String _m(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  final m = d.inMinutes % 60;
  return m > 0 ? '${d.inHours}h${m}m' : '${d.inHours}h';
}

double _maxMs(List<AppUsageBrief> list) =>
    list.isEmpty ? 1.0 : list.first.duration.inMilliseconds.toDouble();

Widget _barRow(AppUsageBrief u, double maxMs, {bool dim = false}) {
  final ratio = (u.duration.inMilliseconds / maxMs).clamp(0.04, 1.0);
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            u.appName,
            style: TextStyle(fontSize: 12, color: dim ? kSub : kText),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: kBg,
              valueColor:
                  AlwaysStoppedAnimation(dim ? kSub.withAlpha(120) : kAccent),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 46,
          child: Text(
            _m(u.duration),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: kSub),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- 纯听歌

class _MusicOnlyBlock extends StatelessWidget {
  final List<AppUsageBrief> music;
  final Duration total;

  const _MusicOnlyBlock({required this.music, required this.total});

  @override
  Widget build(BuildContext context) {
    final maxMs = _maxMs(music);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.headphones, size: 14, color: kSub),
              const SizedBox(width: 6),
              const Text('一直在听', style: TextStyle(fontSize: 11.5, color: kSub)),
              const Spacer(),
              Text(
                _m(total),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: kText),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ...music.take(3).map((u) => _barRow(u, maxMs, dim: true)),
          const SizedBox(height: 4),
          const Divider(color: kBg, height: 14),
          const Text('听歌本身判断不了在做什么，所以下面问你一句',
              style: TextStyle(fontSize: 11, color: kSub)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 常规

class _UsageBlock extends StatelessWidget {
  final List<AppUsageBrief> screen;
  final List<AppUsageBrief> music;
  final Duration screenTotal;
  final Duration musicTotal;
  final AiJudgement? judge;
  final bool judging;
  final List<Attribute> attrs;

  const _UsageBlock({
    required this.screen,
    required this.music,
    required this.screenTotal,
    required this.musicTotal,
    required this.judge,
    required this.judging,
    required this.attrs,
  });

  String _nameOf(String id) {
    for (final a in attrs) {
      if (a.id == id) return a.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _maxMs([...screen, ...music]);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android, size: 14, color: kSub),
              const SizedBox(width: 6),
              const Text('刷手机（已自动判断）',
                  style: TextStyle(fontSize: 11.5, color: kSub)),
              const Spacer(),
              Text(
                _m(screenTotal),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: kText),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (screen.isEmpty)
            const Text('这段没有占注意力的使用',
                style: TextStyle(fontSize: 11.5, color: kSub))
          else
            ...screen.take(10).map((u) => _barRow(u, maxMs)),
            if (screen.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  '还有 ${screen.length - 10} 个更少的没列出',
                  style: const TextStyle(fontSize: 10.5, color: kSub),
                ),
              ),

          if (music.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.headphones, size: 13, color: kSub),
                const SizedBox(width: 6),
                const Text('背景听歌（不算刷手机）',
                    style: TextStyle(fontSize: 11, color: kSub)),
                const Spacer(),
                Text(_m(musicTotal),
                    style: const TextStyle(fontSize: 11, color: kSub)),
              ],
            ),
            const SizedBox(height: 7),
            ...music.take(3).map((u) => _barRow(u, maxMs, dim: true)),
          ],

          const SizedBox(height: 4),
          const Divider(color: kBg, height: 14),

          if (judging)
            const Row(
              children: [
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
                SizedBox(width: 7),
                Text('正在判断影响…',
                    style: TextStyle(fontSize: 11, color: kSub)),
              ],
            )
          else if (judge == null || judge!.effects.isEmpty)
            const Text('这段时间没有明显影响',
                style: TextStyle(fontSize: 11, color: kSub))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('自动判定：',
                    style: TextStyle(fontSize: 11, color: kSub)),
                ...judge!.effects.map((e) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: (e.delta >= 0 ? kUp : kDown).withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_nameOf(e.attrId)}${e.delta >= 0 ? '+' : ''}${e.delta}',
                      style: TextStyle(
                        fontSize: 11,
                        color: e.delta >= 0 ? kUp : kDown,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 昨晚睡眠

class _SleepBlock extends StatelessWidget {
  final SleepVerdict verdict;
  const _SleepBlock({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    final up = v.delta >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bedtime_outlined, size: 14, color: kSub),
              const SizedBox(width: 6),
              const Text('昨晚睡眠（自动推断）',
                  style: TextStyle(fontSize: 11.5, color: kSub)),
              const Spacer(),
              Text(
                v.span.durationText,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: kText),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(v.span.clockText,
                  style: const TextStyle(fontSize: 12.5, color: kText)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (up ? kUp : kDown).withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '睡眠${v.delta >= 0 ? '+' : ''}${v.delta}',
                  style: TextStyle(
                    fontSize: 11,
                    color: up ? kUp : kDown,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(v.reason, style: const TextStyle(fontSize: 11, color: kSub)),
        ],
      ),
    );
  }
}
