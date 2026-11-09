import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/rag_service.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';

/// "Ustoz" paneli: kitob bo'yicha savol-javob (RAG). Javob ostida manbalar —
/// bob, qism va sahifa; bosilsa o'sha joy ochiladi.
class TutorPanel extends StatefulWidget {
  const TutorPanel({
    super.key,
    required this.book,
    required this.chapter,
    required this.section,
    required this.onClose,
    required this.onOpenSource,
  });
  final Book book;
  final Chapter? chapter;
  final Section? section;
  final VoidCallback onClose;
  final void Function(int chapterId, int sectionId) onOpenSource;

  @override
  State<TutorPanel> createState() => _TutorPanelState();
}

class _TutorPanelState extends State<TutorPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  List<ChatMessage> _messages = [];
  bool _thinking = false;
  String _partial = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final msgs = await context.read<AppState>().repo.chat(widget.book.id);
    if (!mounted) return;
    setState(() => _messages = msgs);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _ctrl.text).trim();
    if (q.isEmpty || _thinking) return;
    final app = context.read<AppState>();
    _ctrl.clear();
    setState(() {
      _thinking = true;
      _partial = '';
      _error = null;
      _messages = [
        ..._messages,
        ChatMessage(
          id: -1,
          role: 'user',
          content: q,
          chapterId: widget.chapter?.id,
          sectionId: widget.section?.id,
          createdAt: nowMs(),
        ),
      ];
    });
    _toBottom();
    try {
      await app.content.ask(
        book: widget.book,
        chapter: widget.chapter,
        section: widget.section,
        question: q,
        lang: app.lang,
        onDelta: (t) {
          if (!mounted) return;
          setState(() => _partial = t);
          _toBottom();
        },
      );
    } catch (e) {
      _error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _thinking = false;
      _partial = '';
    });
    await _load();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = context.pal;

    final suggestions = [s.t('sug_simpler'), s.t('sug_example'), s.t('sug_why')];

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(left: BorderSide(color: p.border)),
      ),
      child: Column(
        children: [
          // Sarlavha
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 10, 14),
            child: Row(
              children: [
                const _TutorAvatar(size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('tutor'), style: display(context, size: 17)),
                      Text(s.t('tutor_sub'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: s.t('clear_chat'),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  onPressed: _messages.isEmpty || _thinking
                      ? null
                      : () async {
                          await app.repo.clearChat(widget.book.id);
                          _load();
                        },
                ),
                IconButton(
                  tooltip: s.t('close'),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: _messages.isEmpty && !_thinking
                ? _empty(context, suggestions)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                    itemCount: _messages.length + (_thinking ? 1 : 0) + (_error != null ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i < _messages.length) return _message(context, _messages[i]);
                      if (_thinking && i == _messages.length) return _pending(context);
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: p.dangerSoft, borderRadius: BorderRadius.circular(12)),
                        child: SelectableText(_error ?? '', style: TextStyle(color: p.ink, fontSize: 13)),
                      );
                    },
                  ),
          ),
          // Kontekst + yozish maydoni
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.chapter != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Row(children: [
                      Icon(Icons.my_location_rounded, size: 13, color: p.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            s.t('chapter_n', {'n': widget.chapter!.idx + 1}),
                            if (widget.section != null) s.t('part', {'n': widget.section!.idx + 1}),
                          ].join(' · '),
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      ),
                    ]),
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: p.border),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            minLines: 1,
                            maxLines: 6,
                            decoration: InputDecoration(
                              hintText: s.t('ask_hint'),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: p.ink, foregroundColor: p.bg),
                          tooltip: s.t('send'),
                          onPressed: _thinking ? null : _send,
                          icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, List<String> suggestions) {
    final s = context.s;
    final p = context.pal;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const _TutorAvatar(size: 52),
          const SizedBox(height: 18),
          Text(s.t('tutor_hello'), style: serif(context, size: 22, weight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 8),
          Text(s.t('ask_empty'), style: TextStyle(color: p.inkSoft, height: 1.55)),
          const SizedBox(height: 22),
          for (final sug in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Hoverable(
                onTap: () => _send(sug),
                radius: 12,
                border: p.border,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Icon(Icons.auto_awesome_outlined, size: 16, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(sug, style: const TextStyle(fontWeight: FontWeight.w500))),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pending(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TutorAvatar(size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: _partial.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
                      const SizedBox(width: 10),
                      Text(s.t('searching_book'), style: TextStyle(color: p.muted)),
                    ]),
                  )
                : Md(_partial, fontSize: 14.5),
          ),
        ],
      ),
    );
  }

  Widget _message(BuildContext context, ChatMessage m) {
    final p = context.pal;
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          margin: const EdgeInsets.only(bottom: 16, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: p.ink,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: SelectableText(m.content, style: TextStyle(color: p.bg, height: 1.45)),
        ),
      );
    }
    final sources = SourceRef.listFromJson(m.sourcesJson);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TutorAvatar(size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Md(m.content, fontSize: 14.5),
                if (sources.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final src in sources) _SourceChip(src: src, onTap: widget.onOpenSource)],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.src, required this.onTap});
  final SourceRef src;
  final void Function(int chapterId, int sectionId) onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final label =
        '${s.t('chapter_n', {'n': src.chapterIdx + 1})} › ${s.t('part', {'n': src.sectionIdx + 1})} · ${s.t('page_range', {'n': src.pages})}';
    return Tooltip(
      message: [src.chapterTitle, if (src.snippet.isNotEmpty) src.snippet].join('\n\n'),
      waitDuration: const Duration(milliseconds: 400),
      constraints: const BoxConstraints(maxWidth: 360),
      child: Hoverable(
        onTap: () => onTap(src.chapterId, src.sectionId),
        radius: 8,
        color: p.accentSoft,
        hoverColor: p.accent.withValues(alpha: 0.22),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(5)),
            child: Text('${src.n}',
                style: TextStyle(color: p.onAccent, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _TutorAvatar extends StatelessWidget {
  const _TutorAvatar({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.accent, Color.lerp(p.accent, p.warm, 0.7)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.5),
    );
  }
}
