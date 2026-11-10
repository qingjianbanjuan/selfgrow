import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ai.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

Future<void> showRecordSheet(
  BuildContext context,
  GameStore store, {
  String? initialText,
  Duration? duration,
  bool autoJudge = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordSheet(
      store: store,
      initialText: initialText,
      duration: duration,
      autoJudge: autoJudge,
    ),
  );
}

class _RecordSheet extends StatefulWidget {
  final GameStore store;
  final String? initialText;

  /// 这件事持续了多久（追问流程会带上时间窗口）
  final Duration? duration;
  final bool autoJudge;

  const _RecordSheet({
    required this.store,
    this.initialText,
    this.duration,
    this.autoJudge = false,
  });

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final _textCtrl = TextEditingController();
  bool _aiMode = false;
  bool _busy = false;
  String? _error;

  AiJudgement? _preview;
  String? _previewRaw;

  @override
  void initState() {
    super.initState();
    final txt = widget.initialText;
    if (txt != null && txt.trim().isNotEmpty) {
      _textCtrl.text = txt.trim();
      _aiMode = true;
      if (widget.autoJudge) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _judge());
      }
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  // ---------------- 快捷记录 ----------------

  Future<void> _applyAction(ActionDef a) async {
    // 先抓住外层的 messenger / navigator —— pop 之后 sheet 的 context 就失效了
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final entry = await widget.store.applyEffects(
      label: a.name,
      emoji: a.emoji,
      effects: a.effects,
      source: 'preset',
    );
    if (!mounted) return;

    if (entry == null) {
      _toast('这件事没有产生属性变化（属性可能已满）');
      return;
    }

    // 触感反馈：让"点上了"这件事有物理确认
    HapticFeedback.mediumImpact();

    final detail = entry.effects.map((e) {
      final at = widget.store.attr(e.attrId);
      final n = at?.name ?? e.attrId;
      return '$n${e.delta >= 0 ? '+' : ''}${e.delta}';
    }).join('  ');

    // 先弹提示（挂在 app 级 ScaffoldMessenger 上，关掉面板后仍然可见）
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          Text(a.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已记录 ${a.name}　$detail',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ));

    // 立刻关闭面板：点一下就有效果，不让人猜
    nav.pop();
  }

  // ---------------- AI 判定 ----------------

  Future<void> _judge() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    final j = await AiService.judge(
      text: text,
      attrs: widget.store.attrs,
      groups: widget.store.groups,
      duration: widget.duration,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _preview = j;
      _previewRaw = text;
      if (j == null) _error = '判定失败（网络或 Key 有问题）';
    });
  }

  Future<void> _confirmPreview() async {
    final j = _preview;
    if (j == null) return;
    // 先处理建议的属性
    if (j.suggestions.isNotEmpty) {
      final ok = await _askAddSuggested(j.suggestions);
      if (ok) {
        for (final s in j.suggestions) {
          final g = await widget.store.ensureGroup(s.group);
          await widget.store.addAttribute(
            name: s.name,
            groupId: g.id,
            emoji: s.emoji,
            exp: s.initExp,
          );
        }
        // 新属性创建后重新判定一次，让增减落到新属性上
        await _rejudgeAfterSuggestion();
        return;
      }
    }
    if (j.effects.isEmpty) {
      _toast('这件事没有对应的属性变化');
      return;
    }
    await widget.store.applyEffects(
      label: j.summary,
      emoji: j.emoji,
      effects: j.effects,
      source: 'ai',
      rawText: _previewRaw,
      summary: j.summary,
    );
    if (!mounted) return;
    _toast('已记录：${j.summary}');
    setState(() {
      _preview = null;
      _textCtrl.clear();
    });
  }

  Future<void> _rejudgeAfterSuggestion() async {
    setState(() => _busy = true);
    final j = await AiService.judge(
      text: _previewRaw ?? '',
      attrs: widget.store.attrs,
      groups: widget.store.groups,
      duration: widget.duration,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _preview = j;
    });
    if (j != null && j.effects.isNotEmpty) {
      await widget.store.applyEffects(
        label: j.summary,
        emoji: j.emoji,
        effects: j.effects,
        source: 'ai',
        rawText: _previewRaw,
        summary: j.summary,
      );
      if (!mounted) return;
      _toast('已记录：${j.summary}');
      setState(() {
        _preview = null;
        _textCtrl.clear();
      });
    }
  }

  Future<bool> _askAddSuggested(List<SuggestedAttr> sugg) async {
    final names = sugg.map((s) => '「${s.name}」(${s.group})').join('、');
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('建议新增属性'),
        content: Text(
          'AI 认为这件事涉及到现有属性表里没有的方面：\n\n$names\n\n要加上吗？',
          style: const TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('不要')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('加上')),
        ],
      ),
    );
    return r ?? false;
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('我做了什么',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: kSub),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // 切换
              Row(
                children: [
                  _TabBtn(
                    text: '快捷记录',
                    active: !_aiMode,
                    onTap: () => setState(() => _aiMode = false),
                  ),
                  const SizedBox(width: 8),
                  _TabBtn(
                    text: '说一句',
                    active: _aiMode,
                    onTap: () => setState(() => _aiMode = true),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (!_aiMode) _buildPresets() else _buildAi(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresets() {
    final byCat = <String, List<ActionDef>>{};
    for (final a in widget.store.actions) {
      byCat.putIfAbsent(a.category, () => []).add(a);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: byCat.entries.map((e) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Text(e.key,
                  style: const TextStyle(fontSize: 11.5, color: kSub)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: e.value
                  .map((a) => InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _applyAction(a),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: kSurface2,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${a.emoji} ${a.name}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildAi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _textCtrl,
          maxLines: 3,
          minLines: 2,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            hintText: '刚才在干什么？说一句就行，比如「跑步 30 分钟，出了一身汗」',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _judge,
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('让 AI 判断'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(fontSize: 12, color: kDown)),
        ],
        if (_preview != null) ...[
          const SizedBox(height: 14),
          _buildPreview(_preview!),
        ],
      ],
    );
  }

  Widget _buildPreview(AiJudgement j) {
    final items = j.effects.map((e) {
      final a = widget.store.attr(e.attrId);
      final name = a?.name ?? e.attrId;
      final emoji = a?.emoji ?? '•';
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text('$emoji $name',
                style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text(
              '${e.delta >= 0 ? '+' : ''}${e.delta}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: e.delta >= 0 ? kUp : kDown,
              ),
            ),
          ],
        ),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAccent.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(j.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(j.summary,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              // 显示 AI 采用的时长：影响幅度就是按它算的
              if (j.durationText.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: kBg.withAlpha(120),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 11, color: kSub),
                      const SizedBox(width: 3),
                      Text(j.durationText,
                          style: const TextStyle(fontSize: 10.5, color: kSub)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (j.effects.isEmpty)
            const Text('没有匹配到属性（可以在设置里加新属性）',
                style: TextStyle(fontSize: 12, color: kSub))
          else ...[
            ...items,
            if (j.suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text(
                  '＋ 建议新增：${j.suggestions.map((s) => s.name).join('、')}',
                  style: const TextStyle(fontSize: 11.5, color: kSub),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _preview = null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kSub,
                      side: const BorderSide(color: kSub),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _confirmPreview,
                    style: FilledButton.styleFrom(backgroundColor: kUp),
                    child: const Text('确认记录'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.text, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? kAccent.withAlpha(40) : kSurface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? kAccent : Colors.transparent, width: 1),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: active ? kAccent : kSub,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
