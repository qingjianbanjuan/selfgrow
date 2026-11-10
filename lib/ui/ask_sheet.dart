import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/usage.dart';
import 'theme.dart';

/// 打开 App 时的处理面板。
///
/// 原则：**能自己判断的就不问**。
/// - 手机使用记录 → 直接让 AI 判定并记上，只把结果摆给你看
/// - 手机之外的时间（睡觉/吃饭/上课…）→ 这部分它不知道，才问你
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

  @override
  void initState() {
    super.initState();
    // 一进来就自动判定手机使用那段，不用人催
    WidgetsBinding.instance.addPostFrameCallback((_) => _judgeUsage());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Duration get _gap => DateTime.now().difference(widget.since);
  Duration get _usageTotal => UsageService.totalOf(widget.usage);
  Duration get _offPhoneGap {
    final d = _gap - _usageTotal;
    return d.isNegative ? Duration.zero : d;
  }

  String get _sinceText =>
      '${widget.since.hour.toString().padLeft(2, '0')}:${widget.since.minute.toString().padLeft(2, '0')}';

  String _fmt(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m > 0 ? '$h 小时 $m 分' : '$h 小时';
  }

  String get _usageText => widget.usage.map((u) => u.label).join('、');

  /// 自动判定手机使用这段时间
  Future<void> _judgeUsage() async {
    if (widget.usage.isEmpty) return;
    setState(() {
      _judging = true;
      _error = null;
    });
    final j = await AiService.judge(
      text: '这段时间手机使用：$_usageText',
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

  /// 应用一条判定
  Future<bool> _apply(AiJudgement j, String? rawText) async {
    if (j.effects.isEmpty) return false;
    await widget.store.applyEffects(
      label: j.summary,
      emoji: j.emoji,
      effects: j.effects,
      source: 'ai',
      rawText: rawText,
      summary: j.summary,
    );
    return true;
  }

  /// 主操作：把手机使用那段记上；如果填了文字，再判一次那段
  Future<void> _commit({bool withText = true}) async {
    if (_working) return;
    setState(() => _working = true);

    var count = 0;

    // 1) 手机使用那段
    final uj = _usageJudge;
    if (uj != null && uj.effects.isNotEmpty) {
      if (await _apply(uj, _usageText)) count++;
    }

    // 2) 用户补充的那句
    final extra = withText ? _ctrl.text.trim() : '';
    if (extra.isNotEmpty) {
      final j = await AiService.judge(
        text: extra,
        attrs: widget.store.attrs,
        groups: widget.store.groups,
        duration: _offPhoneGap.inMinutes > 1 ? _offPhoneGap : null,
      );
      if (j != null && j.effects.isNotEmpty) {
        if (await _apply(j, extra)) count++;
      }
    }

    await widget.store.markAsked();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Text(
        count > 0
            ? '已记下 $count 条（${_fmt(_gap)}）'
            : '这段时间没有产生属性变化',
        style: const TextStyle(fontSize: 13),
      ),
    ));
  }

  /// 快速选项：手机之外在干什么
  List<String> get _offPhoneGuesses {
    final g = <String>['在睡觉', '在吃饭', '在上课', '在运动', '在外面逛'];
    if (widget.usage.isEmpty) {
      g.insertAll(0, ['在刷视频', '在打游戏', '在学习']);
    }
    return g.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    final hasUsage = widget.hasUsagePermission && widget.usage.isNotEmpty;
    final offMin = _offPhoneGap.inMinutes;

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
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                hasUsage
                    ? '手机上这段我自己判断，不用你说了'
                    : '这段时间手机上没查到记录',
                style: TextStyle(fontSize: 11, color: kSub.withAlpha(190)),
              ),
              const SizedBox(height: 14),

              // ---------- 手机使用（已自动判定，只展示）----------
              if (!widget.hasUsagePermission) ...[
                _permHint(),
                const SizedBox(height: 14),
              ] else if (hasUsage) ...[
                _UsageBlock(
                  usage: widget.usage,
                  total: _usageTotal,
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

              // ---------- 手机之外（这部分它不知道，才问）----------
              if (offMin >= 15 || !hasUsage) ...[
                Text(
                  hasUsage
                      ? '其余 ${_fmt(_offPhoneGap)} 没有手机记录，在干什么？（可不填）'
                      : '这段时间在干什么？',
                  style: const TextStyle(fontSize: 12, color: kSub),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _offPhoneGuesses
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
                  decoration: const InputDecoration(
                    hintText: '或者说一句，比如「在图书馆看了两小时书」',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ---------- 操作 ----------
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _working
                          ? null
                          : () async {
                              await widget.store.markAsked();
                              if (context.mounted) Navigator.pop(context);
                            },
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
                      onPressed: _working || _judging ? null : () => _commit(),
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
                              hasUsage && _usageJudge != null ? '就这样记' : '记上',
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

// ---------------------------------------------------------------- 手机使用区块

class _UsageBlock extends StatelessWidget {
  final List<AppUsageBrief> usage;
  final Duration total;
  final AiJudgement? judge;
  final bool judging;
  final List<Attribute> attrs;

  const _UsageBlock({
    required this.usage,
    required this.total,
    required this.judge,
    required this.judging,
    required this.attrs,
  });

  String _fmt(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final m = d.inMinutes % 60;
    return m > 0 ? '${d.inHours}h${m}m' : '${d.inHours}h';
  }

  String _nameOf(String id) {
    for (final a in attrs) {
      if (a.id == id) return a.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = usage.isEmpty ? 1 : usage.first.duration.inMilliseconds;

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
              const Text('手机使用（已自动判断）',
                  style: TextStyle(fontSize: 11.5, color: kSub)),
              const Spacer(),
              Text(
                _fmt(total),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: kText),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ...usage.take(6).map((u) {
            final ratio = (u.duration.inMilliseconds / maxMs).clamp(0.04, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(u.appName,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 4,
                        backgroundColor: kBg,
                        valueColor: const AlwaysStoppedAnimation(kAccent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 46,
                    child: Text(
                      _fmt(u.duration),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, color: kSub),
                    ),
                  ),
                ],
              ),
            );
          }),

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