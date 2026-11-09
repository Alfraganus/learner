import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/figure_service.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/async_loader.dart';
import '../widgets/common.dart';
import '../widgets/figure_view.dart';

/// Bitta qism darsi: "qog'oz" sahifa + pastda suzib turuvchi navigatsiya.
class LessonView extends StatelessWidget {
  const LessonView({
    super.key,
    required this.book,
    required this.chapter,
    required this.sections,
    required this.section,
    required this.initialScroll,
    required this.onScroll,
    required this.onPrev,
    required this.onNext,
    this.onLoaded,
  });

  final Book book;
  final Chapter chapter;
  final List<Section> sections;
  final Section section;
  final double initialScroll;
  final ValueChanged<double> onScroll;
  final VoidCallback? onPrev;
  final VoidCallback onNext;
  final VoidCallback? onLoaded;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    return AsyncLoader<Lesson>(
      key: ValueKey('lesson-${section.id}-${app.lang}'),
      loadingText: s.t('generating_lesson'),
      loadingHint: s.t('generating_hint'),
      load: (force) async {
        final hadTitle = section.lessonTitle != null;
        final l = await app.content.lesson(
          book: book,
          chapter: chapter,
          chapterSections: sections,
          section: section,
          lang: app.lang,
          force: force,
        );
        if (!hadTitle || force) onLoaded?.call();
        return l;
      },
      builder: (ctx, lesson, regenerate) => _LessonBody(
        book: book,
        lesson: lesson,
        chapter: chapter,
        section: section,
        total: sections.length,
        initialScroll: initialScroll,
        onScroll: onScroll,
        onPrev: onPrev,
        onNext: onNext,
        onRegenerate: regenerate,
      ),
    );
  }
}

class _LessonBody extends StatefulWidget {
  const _LessonBody({
    required this.book,
    required this.lesson,
    required this.chapter,
    required this.section,
    required this.total,
    required this.initialScroll,
    required this.onScroll,
    required this.onPrev,
    required this.onNext,
    required this.onRegenerate,
  });

  final Book book;
  final Lesson lesson;
  final Chapter chapter;
  final Section section;
  final int total;
  final double initialScroll;
  final ValueChanged<double> onScroll;
  final VoidCallback? onPrev;
  final VoidCallback onNext;
  final VoidCallback onRegenerate;

  @override
  State<_LessonBody> createState() => _LessonBodyState();
}

class _LessonBodyState extends State<_LessonBody> {
  late final ScrollController _scroll;
  Timer? _debounce;
  String? _source;
  bool _sourceOpen = false;
  double _readFrac = 0;
  List<BookFigure> _figs = const [];
  int _figRev = -1;

  /// Qismga tegishli kitob rasmlari (fonda aniqlangan bo'lsa).
  Future<void> _loadFigures() async {
    final app = context.read<AppState>();
    final sec = widget.section;
    try {
      final src = await app.repo.sectionSource(sec.id);
      final figs = await app.figures.sectionFigures(sec, src);
      if (mounted && widget.section.id == sec.id) setState(() => _figs = figs);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _LessonBody old) {
    super.didUpdateWidget(old);
    if (old.section.id != widget.section.id) {
      _figs = const [];
      _figRev = -1;
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _scroll.addListener(_onScroll);
    if (widget.initialScroll > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(widget.initialScroll.clamp(0, _scroll.position.maxScrollExtent));
        }
      });
    }
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      final f = (_scroll.offset / _scroll.position.maxScrollExtent).clamp(0.0, 1.0);
      if ((f - _readFrac).abs() > 0.01) setState(() => _readFrac = f);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (_scroll.hasClients) widget.onScroll(_scroll.offset);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _toggleSource() async {
    final app = context.read<AppState>();
    setState(() => _sourceOpen = !_sourceOpen);
    if (_sourceOpen && _source == null) {
      final src = await app.repo.sectionSource(widget.section.id);
      if (mounted) setState(() => _source = src);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    final l = widget.lesson;
    final sec = widget.section;
    final minutes = (countWordsInLesson(l) / 180).ceil().clamp(1, 999);
    final pages = sec.startPage == sec.endPage ? '${sec.startPage}' : '${sec.startPage}–${sec.endPage}';
    final rev = context.select<AppState, int>((a) => a.figuresRev);
    if (rev != _figRev) {
      _figRev = rev;
      _loadFigures();
    }
    final byLabel = {for (final f in _figs) f.label: f};
    final withFigs = injectFigures(l.content, _figs);

    return Stack(
      children: [
        Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 140),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.paper,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: p.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(64, 56, 64, 56),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Eyebrow(
                            '${s.t('chapter_n', {'n': widget.chapter.idx + 1})}  ·  ${s.t('part_of', {'n': sec.idx + 1, 'm': widget.total})}',
                            color: p.accent,
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: s.t('regenerate'),
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.onRegenerate,
                            icon: Icon(Icons.autorenew_rounded, size: 20, color: p.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SelectableText(l.title,
                          style: serif(context, size: 34, weight: FontWeight.w700, height: 1.2)),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 18,
                        runSpacing: 6,
                        children: [
                          _meta(Icons.menu_book_outlined, s.t('page_range', {'n': pages})),
                          _meta(Icons.schedule_rounded, s.t('minutes_read', {'n': minutes})),
                          _meta(Icons.notes_rounded, s.t('words_src', {'n': sec.wordCount})),
                          if (sec.completed)
                            _meta(Icons.check_circle_rounded, s.t('done'), color: p.success),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Divider(color: p.border),
                      const SizedBox(height: 28),
                      Md(
                        withFigs.markdown,
                        reading: true,
                        imageBuilder: (uri, title, alt) {
                          final f = uri.scheme == 'learner-fig' ? byLabel[uri.path] : null;
                          if (f == null) return const SizedBox.shrink();
                          return FigureView(pdfPath: widget.book.filePath, figure: f);
                        },
                      ),
                      if (withFigs.rest.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Row(children: [
                          Icon(Icons.collections_outlined, color: p.accent, size: 20),
                          const SizedBox(width: 10),
                          Text(s.t('figures_in_part'), style: display(context, size: 17)),
                        ]),
                        const SizedBox(height: 6),
                        for (final f in withFigs.rest)
                          FigureView(pdfPath: widget.book.filePath, figure: f),
                      ],
                      if (l.keyPoints.isNotEmpty) ...[
                        const SizedBox(height: 40),
                        _KeyPoints(points: l.keyPoints),
                      ],
                      if (l.terms.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _Glossary(terms: l.terms),
                      ],
                      const SizedBox(height: 28),
                      Hoverable(
                        onTap: _toggleSource,
                        radius: 14,
                        border: p.border,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined, size: 20, color: p.inkSoft),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.t('original_text'),
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(s.t('original_text_sub'),
                                      style: TextStyle(color: p.muted, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            AnimatedRotation(
                              turns: _sourceOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(Icons.expand_more_rounded, color: p.muted),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        alignment: Alignment.topCenter,
                        child: !_sourceOpen
                            ? const SizedBox(width: double.infinity)
                            : Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: p.surfaceAlt,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: _source == null
                                    ? const LinearProgressIndicator()
                                    : SelectableText(_source!,
                                        style: serif(context, size: 15, color: p.inkSoft, height: 1.6)),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // O'qilganlik chizig'i
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(
            value: _readFrac,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: p.accent,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: _FloatingNav(
              label: s.t('part_of', {'n': sec.idx + 1, 'm': widget.total}),
              onPrev: widget.onPrev,
              onNext: widget.onNext,
              nextLabel: sec.idx + 1 == widget.total ? s.t('finish_chapter') : s.t('mark_done_next'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) {
    final p = context.pal;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color ?? p.muted),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(color: color ?? p.muted, fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }
}

int countWordsInLesson(Lesson l) =>
    l.content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

class _KeyPoints extends StatelessWidget {
  const _KeyPoints({required this.points});
  final List<String> points;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: p.warmSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lightbulb_rounded, color: p.warm, size: 20),
            const SizedBox(width: 10),
            Text(s.t('key_points'), style: display(context, size: 17)),
          ]),
          const SizedBox(height: 16),
          for (var i = 0; i < points.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.warm, shape: BoxShape.circle),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: SelectableText(points[i],
                          style: serif(context, size: 16.5, height: 1.55))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Glossary extends StatelessWidget {
  const _Glossary({required this.terms});
  final List<Term> terms;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.bookmark_border_rounded, color: p.accent, size: 20),
          const SizedBox(width: 10),
          Text(s.t('terms'), style: display(context, size: 17)),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final t in terms)
                Container(
                  width: w,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(t.term,
                          style: TextStyle(fontWeight: FontWeight.w700, color: p.accent)),
                      const SizedBox(height: 4),
                      SelectableText(t.explanation,
                          style: TextStyle(color: p.inkSoft, height: 1.45, fontSize: 13.5)),
                    ],
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
    required this.nextLabel,
  });
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: s.t('prev'),
            child: IconButton(
              onPressed: onPrev,
              icon: Icon(Icons.arrow_back_rounded,
                  color: onPrev == null ? p.bg.withValues(alpha: 0.25) : p.bg),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(label,
                style: TextStyle(color: p.bg.withValues(alpha: 0.75), fontWeight: FontWeight.w600)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: p.warm,
              foregroundColor: const Color(0xFF1D1B16),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            ),
            onPressed: onNext,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(nextLabel),
          ),
        ],
      ),
    );
  }
}
