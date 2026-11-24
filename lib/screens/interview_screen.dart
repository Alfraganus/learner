import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/interview_repo.dart';
import '../models/interview.dart';
import '../services/interview_prompts.dart';
import '../services/video_tools.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import '../widgets/viz_view.dart';
import 'interviews_page.dart';

/// Bitta intervyu tahlili: savollar, nomzod javobi, ekrandagi kod/rasm, baho, to'g'riroq javob va havolalar.
class InterviewScreen extends StatefulWidget {
  const InterviewScreen({super.key, required this.interviewId});
  final int interviewId;

  @override
  State<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends State<InterviewScreen> {
  Interview? _iv;
  List<InterviewItem> _items = [];
  List<Frame> _frames = [];

  /// all — barchasi, wrong — xatolar, marked — belgilanganlar.
  String _filter = 'all';
  String _sig = '';
  final Map<int, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.app;
    final iv = await app.repo.interview(widget.interviewId);
    final items = await app.repo.interviewItems(widget.interviewId);
    final frames = VideoTools.listFrames(app.interviewsSvc.framesDirOf(widget.interviewId));
    if (!mounted) return;
    setState(() {
      _iv = iv;
      _items = items;
      _frames = frames;
    });
  }

  /// Belgilarni saqlash (muhim, izoh, parchalar) va ro'yxatdagi sonni yangilash.
  Future<void> _setMarks(InterviewItem item, {bool? starred, String? note, List<String>? highlights}) async {
    final app = context.app;
    final i = _items.indexWhere((x) => x.id == item.id);
    if (i < 0) return;
    final cur = _items[i];
    final starredChanged = starred != null && starred != cur.starred;
    setState(() => _items[i] = cur.copyWith(starred: starred, note: note, highlights: highlights));
    await app.repo.updateItemMarks(item.id, starred: starred, note: note, highlights: highlights);
    if (starredChanged) await app.refresh();
  }

  InterviewItem _current(InterviewItem item) => _items.firstWhere((x) => x.id == item.id, orElse: () => item);

  Future<void> _toggleStar(InterviewItem item) async {
    final cur = _current(item);
    if (!cur.starred) return _setMarks(cur, starred: true);
    final hasData = cur.note.trim().isNotEmpty || cur.highlights.isNotEmpty;
    if (hasData && !await confirm(context, context.s.t('iv_unmark_q'))) return;
    await _setMarks(cur, starred: false, note: '', highlights: const []);
  }

  Future<void> _addHighlight(InterviewItem item, String text) async {
    var t = text.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (t.isEmpty) return;
    if (t.length > 1500) t = '${t.substring(0, 1500)}…';
    final cur = _current(item);
    if (cur.highlights.contains(t)) return;
    await _setMarks(cur, starred: true, highlights: [...cur.highlights, t]);
  }

  /// Belgilangan savolga o'tish (filtr uni yashirsa — "Barchasi"ga o'tamiz).
  void _goTo(InterviewItem item) {
    if (!_visible(item)) setState(() => _filter = 'all');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[item.id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          alignment: 0.02,
        );
      }
    });
  }

  bool _visible(InterviewItem i) => switch (_filter) {
    'wrong' => i.analyzed && i.verdict != 'correct',
    'marked' => i.hasMarks,
    _ => true,
  };

  Frame? _frameAt(double t) {
    if (_frames.isEmpty) return null;
    var best = _frames.first;
    for (final f in _frames) {
      if ((f.time - t).abs() < (best.time - t).abs()) best = f;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.watch<AppState>();
    final s = app.s;
    // Ro'yxatdagi holat o'zgarsa (yangi savol tahlil qilindi) — qayta yuklaymiz.
    final live = app.interviews.where((i) => i.id == widget.interviewId).firstOrNull;
    final sig = live == null
        ? ''
        : '${live.status}|${live.statusMessage}|${live.progress}|${live.itemCount}|${live.correct}|${live.partial}|${live.wrong}';
    if (sig != _sig) {
      _sig = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final iv = _iv;
    if (iv == null) return Scaffold(body: LoadingView(s.t('iv_step_info')));
    final busy = app.interviewsSvc.isActive(iv.id) || iv.status == InterviewStatus.processing;
    final shown = _items.where(_visible).toList();
    final marked = _items.where((i) => i.hasMarks).toList();
    final summary = iv.summary;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(iv.displayTitle, overflow: TextOverflow.ellipsis, style: display(context, size: 17)),
        actions: [
          TextButton.icon(
            onPressed: () => openUrl(iv.url),
            icon: Icon(Icons.smart_display_outlined, color: p.danger),
            label: Text(s.t('iv_open_video')),
          ),
          if (!busy)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'again' && await confirm(context, s.t('iv_reanalyze_body'))) {
                  app.interviewsSvc.reanalyze(iv.id);
                  await app.refresh();
                }
                if (v == 'delete' && context.mounted && await confirm(context, s.t('iv_delete_q'))) {
                  await app.deleteInterview(iv.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'again', child: Text(s.t('iv_reanalyze'))),
                PopupMenuItem(value: 'delete', child: Text(s.t('delete'))),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sarlavha
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (iv.thumbnailUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 200,
                              height: 112,
                              child: Image.network(
                                iv.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(color: p.surfaceAlt),
                              ),
                            ),
                          ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                iv.displayTitle,
                                style: serif(context, size: 24, weight: FontWeight.w700, height: 1.25),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  if ((iv.channel ?? '').isNotEmpty) iv.channel!,
                                  if (iv.duration > 0) InterviewPrompts.mmss(iv.duration.toDouble()),
                                  if (_items.isNotEmpty) s.t('iv_questions', {'n': _items.length}),
                                  if ('${summary?['role'] ?? ''}'.isNotEmpty) '${summary!['role']}',
                                ].join(' · '),
                                style: TextStyle(color: p.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (iv.isError)
                      _Banner(
                        color: p.danger,
                        soft: p.dangerSoft,
                        icon: Icons.error_outline_rounded,
                        text: translateStatus(s, iv.statusMessage),
                        action: TextButton(
                          onPressed: () async {
                            app.interviewsSvc.retry(iv.id);
                            await app.refresh();
                          },
                          child: Text(s.t('iv_retry')),
                        ),
                      )
                    else if (busy)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    translateStatus(s, iv.statusMessage),
                                    style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: iv.progress,
                                minHeight: 5,
                                backgroundColor: p.surface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (summary != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: p.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ('${summary['summary'] ?? ''}'.isNotEmpty)
                              Text('${summary['summary']}', style: TextStyle(height: 1.5, color: p.ink, fontSize: 15)),
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              runSpacing: 10,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      s.t('iv_score'),
                                      style: TextStyle(fontWeight: FontWeight.w700, color: p.inkSoft),
                                    ),
                                    const SizedBox(width: 12),
                                    ScoreChip(
                                      icon: Icons.check_circle_rounded,
                                      color: p.success,
                                      n: iv.correct,
                                      label: s.t('iv_correct'),
                                    ),
                                    const SizedBox(width: 6),
                                    ScoreChip(
                                      icon: Icons.adjust_rounded,
                                      color: p.warm,
                                      n: iv.partial,
                                      label: s.t('iv_partial'),
                                    ),
                                    const SizedBox(width: 6),
                                    ScoreChip(
                                      icon: Icons.cancel_rounded,
                                      color: p.danger,
                                      n: iv.wrong,
                                      label: s.t('iv_incorrect'),
                                    ),
                                  ],
                                ),
                                SegmentedButton<String>(
                                  segments: [
                                    ButtonSegment(value: 'all', label: Text(s.t('iv_all'))),
                                    ButtonSegment(value: 'wrong', label: Text(s.t('iv_filter_wrong'))),
                                    ButtonSegment(
                                      value: 'marked',
                                      icon: Icon(Icons.flag_rounded, size: 16, color: p.accent),
                                      label: Text('${s.t('iv_filter_marked')} ${marked.length}'),
                                    ),
                                  ],
                                  selected: {_filter},
                                  showSelectedIcon: false,
                                  onSelectionChanged: (v) => setState(() => _filter = v.first),
                                ),
                              ],
                            ),
                            if (summary['frames'] == 0) ...[
                              const SizedBox(height: 12),
                              Text(s.t('iv_no_frames'), style: TextStyle(color: p.muted, fontSize: 13)),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (marked.isNotEmpty) ...[const SizedBox(height: 16), _MarkedList(items: marked, onTap: _goTo)],
                    if (_filter == 'marked' && marked.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: _Banner(
                          color: p.accent,
                          soft: p.accentSoft,
                          icon: Icons.outlined_flag_rounded,
                          text: s.t('iv_marked_empty'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    for (final item in shown)
                      KeyedSubtree(
                        key: _keys.putIfAbsent(item.id, GlobalKey.new),
                        child: _QuestionCard(
                          key: ValueKey(item.id),
                          iv: iv,
                          item: item,
                          total: _items.length,
                          frameAt: _frameAt,
                          onToggleStar: () => _toggleStar(item),
                          onNote: (t) => _setMarks(_current(item), note: t, starred: true),
                          onAddHighlight: (t) => _addHighlight(item, t),
                          onRemoveHighlight: (t) {
                            final cur = _current(item);
                            _setMarks(cur, highlights: [...cur.highlights]..remove(t));
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Belgilaganlarim": muhim deb belgilangan savollar, izohlar va parchalar. Bosilsa — savolga o'tadi.
class _MarkedList extends StatelessWidget {
  const _MarkedList({required this.items, required this.onTap});
  final List<InterviewItem> items;
  final void Function(InterviewItem) onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 20, color: p.accent),
              const SizedBox(width: 8),
              Text(s.t('iv_marked_title'), style: display(context, size: 17)),
              const SizedBox(width: 8),
              Text(
                '${items.length}',
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Hoverable(
                onTap: () => onTap(it),
                radius: 12,
                color: p.surface,
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(7)),
                      child: Text(
                        '${it.idx + 1}',
                        style: TextStyle(color: p.surface, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            it.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, color: p.ink, height: 1.35),
                          ),
                          if (it.note.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.edit_note_rounded, size: 17, color: p.accent),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      it.note.trim(),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final h in it.highlights)
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              padding: const EdgeInsets.only(left: 10),
                              decoration: BoxDecoration(
                                border: Border(left: BorderSide(color: p.accent, width: 2.5)),
                              ),
                              child: Text(
                                h,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.inkSoft, fontSize: 13.5, height: 1.4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: s.t('iv_go_question'),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Icon(Icons.arrow_downward_rounded, size: 18, color: p.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.soft, required this.icon, required this.text, this.action});
  final Color color, soft;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(text, style: TextStyle(color: context.pal.ink, height: 1.4)),
        ),
        ?action,
      ],
    ),
  );
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    super.key,
    required this.iv,
    required this.item,
    required this.total,
    required this.frameAt,
    required this.onToggleStar,
    required this.onNote,
    required this.onAddHighlight,
    required this.onRemoveHighlight,
  });
  final Interview iv;
  final InterviewItem item;
  final int total;
  final Frame? Function(double t) frameAt;
  final VoidCallback onToggleStar;
  final ValueChanged<String> onNote;
  final ValueChanged<String> onAddHighlight;
  final ValueChanged<String> onRemoveHighlight;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  bool _showOriginal = false;
  late final TextEditingController _note = TextEditingController(text: widget.item.note);
  Timer? _noteSave;

  /// SelectionArea'da hozir tanlangan matn (o'ng tugma menyusidagi "Muhim deb belgilash" uchun).
  String _selected = '';

  @override
  void didUpdateWidget(covariant _QuestionCard old) {
    super.didUpdateWidget(old);
    // Belgi olib tashlanganda izoh ham tozalanadi.
    if (widget.item.note != old.item.note && widget.item.note != _note.text && _noteSave == null) {
      _note.text = widget.item.note;
    }
  }

  @override
  void dispose() {
    if (_noteSave?.isActive ?? false) {
      _noteSave!.cancel();
      widget.onNote(_note.text);
    }
    _note.dispose();
    super.dispose();
  }

  void _onNoteChanged(String v) {
    _noteSave?.cancel();
    _noteSave = Timer(const Duration(milliseconds: 600), () {
      _noteSave = null;
      widget.onNote(v);
    });
  }

  /// Matn tanlanadigan hudud: o'ng tugma menyusiga "Muhim deb belgilash" qo'shiladi.
  Widget _selectable(Widget child) {
    final s = context.s;
    return SelectionArea(
      onSelectionChanged: (c) => _selected = c?.plainText ?? '',
      contextMenuBuilder: (ctx, st) {
        final sel = _selected.trim();
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: st.contextMenuAnchors,
          buttonItems: [
            if (sel.isNotEmpty)
              ContextMenuButtonItem(
                label: s.t('iv_mark_sel'),
                onPressed: () {
                  ContextMenuController.removeAny();
                  widget.onAddHighlight(sel);
                },
              ),
            ...st.contextMenuButtonItems,
          ],
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final item = widget.item;
    final (Color vc, Color vsoft, IconData vi, String vl) = switch (item.verdict) {
      'correct' => (p.success, p.successSoft, Icons.check_circle_rounded, s.t('iv_correct')),
      'partial' => (p.warm, p.warmSoft, Icons.adjust_rounded, s.t('iv_partial')),
      'incorrect' => (p.danger, p.dangerSoft, Icons.cancel_rounded, s.t('iv_incorrect')),
      'no_answer' => (p.danger, p.dangerSoft, Icons.do_not_disturb_on_outlined, s.t('iv_no_answer')),
      _ => (p.muted, p.surfaceAlt, Icons.hourglass_empty_rounded, s.t('iv_pending')),
    };

    Widget section(IconData icon, String title, Widget child, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color ?? p.accent),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  color: color ?? p.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );

    final screen = item.screen;
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: item.starred ? Border.all(color: p.accent, width: 1.6) : Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bosh qism
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        '${item.idx + 1}/${widget.total}',
                        style: TextStyle(color: p.surface, fontWeight: FontWeight.w800, fontSize: 12.5),
                      ),
                    ),
                    _chip(context, s.t('iv_kind_${item.kind}')),
                    if (item.topic.isNotEmpty) _chip(context, item.topic),
                    ActionChip(
                      avatar: Icon(Icons.play_circle_outline_rounded, size: 16, color: p.danger),
                      label: Text(InterviewPrompts.mmss(item.start)),
                      tooltip: s.t('iv_open_at', {'t': InterviewPrompts.mmss(item.start)}),
                      onPressed: () => openUrl(widget.iv.linkAt(item.start)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: vsoft, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(vi, size: 15, color: vc),
                          const SizedBox(width: 5),
                          Text(
                            vl,
                            style: TextStyle(color: vc, fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              item.starred
                  ? IconButton.filledTonal(
                      tooltip: s.t('iv_unmark'),
                      onPressed: widget.onToggleStar,
                      style: IconButton.styleFrom(backgroundColor: p.accentSoft),
                      icon: Icon(Icons.flag_rounded, color: p.accent),
                    )
                  : IconButton(
                      tooltip: s.t('iv_mark'),
                      onPressed: widget.onToggleStar,
                      icon: Icon(Icons.outlined_flag_rounded, color: p.muted),
                    ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _body(context, item, screen, section, vc: vc, vsoft: vsoft, vi: vi),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    InterviewItem item,
    List<ScreenCapture> screen,
    Widget Function(IconData icon, String title, Widget child, {Color? color}) section, {
    required Color vc,
    required Color vsoft,
    required IconData vi,
  }) {
    final p = context.pal;
    final s = context.s;
    return [
      const SizedBox(height: 14),
      _selectable(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.text, style: serif(context, size: 20, weight: FontWeight.w700, height: 1.4)),
            if (item.original.isNotEmpty && item.original != item.text) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => setState(() => _showOriginal = !_showOriginal),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showOriginal ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        size: 18,
                        color: p.muted,
                      ),
                      Text(s.t('iv_original'), style: TextStyle(color: p.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              if (_showOriginal)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Md(item.original, fontSize: 14, selectable: false),
                ),
            ],
          ],
        ),
      ),
      if (item.starred) _marksBox(context, item),
      if (!item.analyzed)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Row(
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.muted)),
              const SizedBox(width: 10),
              Text(s.t('iv_pending'), style: TextStyle(color: p.muted)),
            ],
          ),
        )
      else
        _selectable(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              section(
                Icons.person_outline_rounded,
                s.t('iv_candidate'),
                item.candidateAnswer.trim().isEmpty
                    ? Text(s.t('iv_candidate_none'), style: TextStyle(color: p.muted))
                    : RichMd(item.candidateAnswer, fontSize: 15, selectable: false),
                color: p.inkSoft,
              ),
              if (screen.isNotEmpty)
                section(
                  Icons.desktop_windows_outlined,
                  s.t('iv_screen'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final c in screen)
                        _ScreenView(capture: c, frame: c.showImage ? widget.frameAt(c.time) : null),
                    ],
                  ),
                  color: p.inkSoft,
                ),
              if (item.verdictReason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: vsoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: vc, width: 3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(vi, size: 18, color: vc),
                        const SizedBox(width: 10),
                        Expanded(child: Md(item.verdictReason, fontSize: 14.5, selectable: false)),
                      ],
                    ),
                  ),
                ),
              if (item.betterAnswer.isNotEmpty)
                section(
                  Icons.lightbulb_outline_rounded,
                  s.t(item.verdict == 'correct' ? 'iv_better_ok' : 'iv_better'),
                  RichMd(item.betterAnswer, fontSize: 15, selectable: false),
                  color: p.success,
                ),
              if (item.keyPoints.isNotEmpty)
                section(
                  Icons.push_pin_outlined,
                  s.t('iv_key_points'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final k in item.keyPoints)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 7, right: 10),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: p.warm, shape: BoxShape.circle),
                                ),
                              ),
                              Expanded(child: Md(k, fontSize: 14.5, selectable: false)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  color: p.warm,
                ),
              if (item.resources.isNotEmpty)
                section(
                  Icons.school_outlined,
                  s.t('iv_resources'),
                  Column(
                    children: [
                      for (final r in item.resources)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Hoverable(
                            onTap: () => openUrl(r.url),
                            radius: 12,
                            border: p.border,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.link_rounded, color: p.accent, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.title,
                                        style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
                                      ),
                                      Text(
                                        Uri.tryParse(r.url)?.host ?? r.url,
                                        style: TextStyle(color: p.accent, fontSize: 12),
                                      ),
                                      if (r.why.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(r.why, style: TextStyle(color: p.inkSoft, fontSize: 13)),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.open_in_new_rounded, size: 16, color: p.muted),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  /// Mening belgilarim: belgilangan parchalar va shaxsiy izoh.
  Widget _marksBox(BuildContext context, InterviewItem item) {
    final p = context.pal;
    final s = context.s;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 16, color: p.accent),
              const SizedBox(width: 8),
              Text(
                s.t('iv_my_notes').toUpperCase(),
                style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: p.accent),
              ),
            ],
          ),
          for (final h in item.highlights)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: p.accent, width: 3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(h, style: TextStyle(color: p.ink, height: 1.45, fontSize: 14)),
                    ),
                  ),
                  IconButton(
                    tooltip: s.t('iv_hl_remove'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onRemoveHighlight(h),
                    icon: Icon(Icons.close_rounded, size: 16, color: p.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            onChanged: _onNoteChanged,
            minLines: 1,
            maxLines: 6,
            style: TextStyle(color: p.ink, fontSize: 14, height: 1.45),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: p.surface,
              hintText: s.t('iv_note_hint'),
              prefixIcon: Icon(Icons.edit_note_rounded, color: p.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(color: p.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Ekranda ko'rsatilgan narsa: kadr rasmi (bosilsa kattalashadi) va undagi kod/matn.
class _ScreenView extends StatelessWidget {
  const _ScreenView({required this.capture, required this.frame});
  final ScreenCapture capture;
  final Frame? frame;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final c = capture;
    final f = frame;
    final isCode = c.kind == 'code' || c.kind == 'terminal';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: p.surfaceAlt,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(isCode ? Icons.code_rounded : Icons.image_outlined, size: 16, color: p.inkSoft),
                const SizedBox(width: 8),
                Text(
                  [s.t('iv_screen_${c.kind}'), if (c.language.isNotEmpty) c.language].join(' · '),
                  style: TextStyle(fontWeight: FontWeight.w700, color: p.inkSoft, fontSize: 13),
                ),
                const Spacer(),
                Text(InterviewPrompts.mmss(c.time), style: TextStyle(color: p.muted, fontSize: 12.5)),
              ],
            ),
          ),
          if (f != null && File(f.path).existsSync())
            InkWell(
              onTap: () => showDialog(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.8),
                builder: (ctx) => Dialog(
                  insetPadding: const EdgeInsets.all(24),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      InteractiveViewer(maxScale: 6, child: Image.file(File(f.path), fit: BoxFit.contain)),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: IconButton.filledTonal(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: Container(
                color: Colors.black,
                constraints: const BoxConstraints(maxHeight: 420),
                child: Image.file(File(f.path), fit: BoxFit.contain),
              ),
            ),
          if (c.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: isCode
                  ? Md('```${c.language.toLowerCase()}\n${c.content.trimRight()}\n```', fontSize: 15, selectable: false)
                  : Md(c.content, fontSize: 14.5, selectable: false),
            ),
        ],
      ),
    );
  }
}
