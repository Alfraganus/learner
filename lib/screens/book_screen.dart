import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/rag_service.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import 'chat_panel.dart';
import 'lesson_view.dart';
import 'review_views.dart';

enum ViewKind { lesson, end, qa, quiz, exercises }

/// O'qish studiyasi: chapda o'quv yo'li, o'rtada qog'oz sahifa, o'ngda AI ustoz.
class BookScreen extends StatefulWidget {
  const BookScreen({super.key, required this.bookId});
  final int bookId;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  Book? _book;
  List<Chapter> _chapters = [];
  Map<int, List<Section>> _sections = {};
  final Map<int, QuizAttempt?> _quiz = {};
  String? _loadedLang;
  String? _error;

  int? _chapterId;
  int? _sectionId;
  ViewKind _view = ViewKind.lesson;
  double _initialScroll = 0;
  bool _tutorOpen = true;
  bool _pathOpen = true;
  final Set<int> _expanded = {};

  AppState get app => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final book = await app.repo.book(widget.bookId);
      if (book == null) return;
      _book = book;
      await _loadStructure();
      _restorePosition(book);
      _translateTitlesIfNeeded();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadStructure() async {
    final lang = app.lang;
    _chapters = await app.repo.chapters(widget.bookId, lang);
    final all = await app.repo.bookSections(widget.bookId, lang);
    final map = <int, List<Section>>{};
    for (final s in all) {
      map.putIfAbsent(s.chapterId, () => []).add(s);
    }
    _sections = map;
    for (final c in _chapters) {
      _quiz[c.id] = await app.repo.bestQuizAttempt(c.id);
    }
    _loadedLang = lang;
  }

  void _translateTitlesIfNeeded() {
    if (_chapters.any((c) => c.localTitle == null)) {
      app.content.ensureChapterTitles(widget.bookId, app.lang).then((_) async {
        if (!mounted) return;
        await _loadStructure();
        setState(() {});
      }, onError: (_) {});
    }
  }

  void _restorePosition(Book book) {
    final chapterIds = _chapters.map((c) => c.id).toSet();
    if (book.lastChapterId != null && chapterIds.contains(book.lastChapterId)) {
      _chapterId = book.lastChapterId;
      final view = ViewKind.values.where((v) => v.name == book.lastView).firstOrNull;
      _view = view ?? ViewKind.lesson;
      final secs = _sections[_chapterId] ?? [];
      if (_view == ViewKind.lesson) {
        final sec = secs.where((s) => s.id == book.lastSectionId).firstOrNull;
        _sectionId = sec?.id ?? secs.firstOrNull?.id;
        _initialScroll = sec != null ? (book.lastScroll ?? 0) : 0;
      }
    } else {
      for (final c in _chapters) {
        final sec = (_sections[c.id] ?? []).where((s) => !s.completed).firstOrNull;
        if (sec != null) {
          _chapterId = c.id;
          _sectionId = sec.id;
          break;
        }
      }
      _chapterId ??= _chapters.firstOrNull?.id;
      _sectionId ??= _sections[_chapterId]?.firstOrNull?.id;
      _view = ViewKind.lesson;
    }
    if (_chapterId != null) _expanded.add(_chapterId!);
    _savePosition();
  }

  void _savePosition([double scroll = 0]) {
    app.repo.savePosition(widget.bookId,
        chapterId: _chapterId,
        sectionId: _view == ViewKind.lesson ? _sectionId : null,
        view: _view.name,
        scroll: scroll);
  }

  // ---------------- Navigatsiya ----------------
  Chapter? get _chapter => _chapters.where((c) => c.id == _chapterId).firstOrNull;
  List<Section> get _chapterSections => _sections[_chapterId] ?? const [];
  Section? get _section => _chapterSections.where((s) => s.id == _sectionId).firstOrNull;

  void _goSection(Chapter c, Section s) {
    setState(() {
      _chapterId = c.id;
      _sectionId = s.id;
      _view = ViewKind.lesson;
      _initialScroll = 0;
      _expanded.add(c.id);
    });
    _savePosition();
    _prefetchAround(c, s);
  }

  /// Manba yoki qidiruv natijasidan o'sha joyni ochish.
  void _openSource(int chapterId, int sectionId) {
    final c = _chapters.where((x) => x.id == chapterId).firstOrNull;
    final s = (_sections[chapterId] ?? []).where((x) => x.id == sectionId).firstOrNull;
    if (c != null && s != null) _goSection(c, s);
  }

  void _goView(Chapter c, ViewKind v) {
    setState(() {
      _chapterId = c.id;
      _view = v;
      _sectionId = null;
      _expanded.add(c.id);
    });
    _savePosition();
  }

  void _prefetchAround(Chapter c, Section s) {
    final book = _book;
    if (book == null) return;
    final secs = _sections[c.id] ?? [];
    final i = secs.indexWhere((x) => x.id == s.id);
    if (i >= 0 && i + 1 < secs.length) {
      app.content.prefetch(
          book: book, chapter: c, chapterSections: secs, section: secs[i + 1], lang: app.lang);
    }
    if (i == secs.length - 1) app.content.prefetchReviews(book, c, app.lang);
  }

  Future<void> _refreshSections() async {
    await _loadStructure();
    if (mounted) setState(() {});
  }

  Future<void> _next() async {
    final c = _chapter;
    final s = _section;
    if (c == null || s == null) return;
    await app.repo.markSectionDone(s);
    await _refreshSections();
    final secs = _sections[c.id] ?? [];
    final i = secs.indexWhere((x) => x.id == s.id);
    if (i + 1 < secs.length) {
      _goSection(c, secs[i + 1]);
    } else {
      _goView(c, ViewKind.end);
    }
  }

  void _prev() {
    final c = _chapter;
    final s = _section;
    if (c == null || s == null) return;
    final secs = _chapterSections;
    final i = secs.indexWhere((x) => x.id == s.id);
    if (i > 0) {
      _goSection(c, secs[i - 1]);
    } else {
      final ci = _chapters.indexWhere((x) => x.id == c.id);
      if (ci > 0) _goView(_chapters[ci - 1], ViewKind.end);
    }
  }

  bool get _hasPrev {
    final c = _chapter;
    final s = _section;
    if (c == null || s == null) return false;
    return s.idx > 0 || _chapters.indexWhere((x) => x.id == c.id) > 0;
  }

  Chapter? get _nextChapter {
    final ci = _chapters.indexWhere((x) => x.id == _chapterId);
    return ci >= 0 && ci + 1 < _chapters.length ? _chapters[ci + 1] : null;
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final appW = context.watch<AppState>();
    final p = context.pal;

    if (_loadedLang != null && _loadedLang != appW.lang) {
      _loadedLang = appW.lang;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _refreshSections();
        _translateTitlesIfNeeded();
      });
    }

    final book = _book;
    if (_error != null) return Scaffold(body: ErrorView(_error!));
    if (book == null) return Scaffold(body: LoadingView(appW.s.t('processing')));

    final total = _sections.values.fold<int>(0, (a, l) => a + l.length);
    final done = _sections.values.fold<int>(0, (a, l) => a + l.where((x) => x.completed).length);
    final progress = total == 0 ? 0.0 : done / total;

    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          _TopBar(
            book: book,
            chapter: _chapter,
            section: _view == ViewKind.lesson ? _section : null,
            progress: progress,
            pathOpen: _pathOpen,
            tutorOpen: _tutorOpen,
            onTogglePath: () => setState(() => _pathOpen = !_pathOpen),
            onToggleTutor: () => setState(() => _tutorOpen = !_tutorOpen),
            onOpenSource: _openSource,
          ),
          Expanded(
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: _pathOpen ? 316 : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 316,
                      maxWidth: 316,
                      child: _PathPanel(
                        chapters: _chapters,
                        sections: _sections,
                        quiz: _quiz,
                        expanded: _expanded,
                        currentChapterId: _chapterId,
                        currentSectionId: _view == ViewKind.lesson ? _sectionId : null,
                        view: _view,
                        onToggle: (id) => setState(
                            () => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id)),
                        onSection: _goSection,
                        onView: _goView,
                      ),
                    ),
                  ),
                ),
                Expanded(child: _buildMain()),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: _tutorOpen ? 410 : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 410,
                      maxWidth: 410,
                      child: TutorPanel(
                        key: ValueKey('tutor-${book.id}'),
                        book: book,
                        chapter: _chapter,
                        section: _view == ViewKind.lesson ? _section : null,
                        onClose: () => setState(() => _tutorOpen = false),
                        onOpenSource: _openSource,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain() {
    final book = _book!;
    final c = _chapter;
    if (c == null) return const SizedBox();
    final child = switch (_view) {
      ViewKind.lesson => _section == null
          ? const SizedBox()
          : LessonView(
              key: ValueKey('lv-${_section!.id}'),
              book: book,
              chapter: c,
              sections: _chapterSections,
              section: _section!,
              initialScroll: _initialScroll,
              onScroll: (o) => app.repo.saveScroll(book.id, o),
              onPrev: _hasPrev ? _prev : null,
              onNext: _next,
              onLoaded: _refreshSections,
            ),
      ViewKind.end => ChapterEndView(
          key: ValueKey('end-${c.id}'),
          chapter: c,
          onQa: () => _goView(c, ViewKind.qa),
          onQuiz: () => _goView(c, ViewKind.quiz),
          onExercises: () => _goView(c, ViewKind.exercises),
          onNextChapter: _nextChapter == null
              ? null
              : () {
                  final next = _nextChapter!;
                  final first = (_sections[next.id] ?? []).firstOrNull;
                  if (first != null) _goSection(next, first);
                },
        ),
      ViewKind.qa => QaView(key: ValueKey('qa-${c.id}'), book: book, chapter: c),
      ViewKind.quiz => QuizView(
          key: ValueKey('quiz-${c.id}'),
          book: book,
          chapter: c,
          onFinished: () async {
            _quiz[c.id] = await app.repo.bestQuizAttempt(c.id);
            if (mounted) setState(() {});
          },
        ),
      ViewKind.exercises => ExercisesView(key: ValueKey('ex-${c.id}'), book: book, chapter: c),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: child,
    );
  }
}

// ============================================================ Yuqori panel
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.book,
    required this.chapter,
    required this.section,
    required this.progress,
    required this.pathOpen,
    required this.tutorOpen,
    required this.onTogglePath,
    required this.onToggleTutor,
    required this.onOpenSource,
  });
  final Book book;
  final Chapter? chapter;
  final Section? section;
  final double progress;
  final bool pathOpen;
  final bool tutorOpen;
  final VoidCallback onTogglePath;
  final VoidCallback onToggleTutor;
  final void Function(int, int) onOpenSource;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    final where = [
      if (chapter != null) s.t('chapter_n', {'n': chapter!.idx + 1}),
      if (chapter != null) chapter!.displayTitle,
    ].join(' · ');

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: s.t('back'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          IconButton(
            tooltip: s.t('learning_path'),
            onPressed: onTogglePath,
            icon: Icon(pathOpen ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined,
                color: pathOpen ? p.accent : p.inkSoft),
          ),
          const SizedBox(width: 8),
          BookCover(title: book.title, width: 30, showText: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _BookSearch(book: book, onOpen: onOpenSource),
          const SizedBox(width: 16),
          Tooltip(
            message: s.t('progress', {'p': (progress * 100).round()}),
            child: ProgressRing(value: progress, size: 38, stroke: 3.5, color: p.success),
          ),
          const SizedBox(width: 12),
          Hoverable(
            onTap: onToggleTutor,
            radius: 12,
            color: tutorOpen ? p.accentSoft : p.surfaceAlt,
            hoverColor: p.accentSoft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: p.accent),
              const SizedBox(width: 8),
              Text(s.t('tutor'), style: TextStyle(fontWeight: FontWeight.w700, color: p.accent)),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Kitob ichidan tezkor qidiruv (FTS5, Claude'siz).
class _BookSearch extends StatefulWidget {
  const _BookSearch({required this.book, required this.onOpen});
  final Book book;
  final void Function(int chapterId, int sectionId) onOpen;

  @override
  State<_BookSearch> createState() => _BookSearchState();
}

class _BookSearchState extends State<_BookSearch> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _overlay = OverlayPortalController();
  Timer? _debounce;
  List<RagHit> _hits = [];
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 180), () {
          if (mounted && !_focus.hasFocus) _overlay.hide();
        });
      } else if (_ctrl.text.trim().isNotEmpty) {
        _overlay.show();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _hits = [];
        _searched = false;
      });
      _overlay.hide();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final app = context.read<AppState>();
      final hits = await app.content.searchBook(widget.book.id, v, app.lang);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searched = true;
      });
      _overlay.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (ctx) => Positioned(
          width: 480,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: Material(
              color: p.surface,
              elevation: 12,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 480),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.border),
                ),
                child: _hits.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_searched ? s.t('search_none') : '',
                            style: TextStyle(color: p.muted)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _hits.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (ctx, i) => _hit(ctx, _hits[i]),
                      ),
              ),
            ),
          ),
        ),
        child: SizedBox(
          width: 320,
          height: 42,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            onChanged: _onChanged,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: s.t('search_in_book'),
              isDense: true,
              fillColor: p.surfaceAlt,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: p.muted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hit(BuildContext context, RagHit h) {
    final s = context.s;
    final p = context.pal;
    final pages = h.pageStart == h.pageEnd ? '${h.pageStart}' : '${h.pageStart}–${h.pageEnd}';
    return Hoverable(
      onTap: () {
        widget.onOpen(h.chapterId, h.sectionId);
        _overlay.hide();
        _focus.unfocus();
      },
      radius: 10,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '${s.t('chapter_n', {'n': h.chapterIdx + 1})} › ${s.t('part', {'n': h.sectionIdx + 1})}  ·  ${h.localTitle ?? h.chapterTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
            Text(s.t('page_range', {'n': pages}), style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          _Snippet(h.snippet),
        ],
      ),
    );
  }
}

/// «...» bilan belgilangan mosliklarni ajratib ko'rsatadi.
class _Snippet extends StatelessWidget {
  const _Snippet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final spans = <TextSpan>[];
    final re = RegExp(r'«([^»]*)»');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(
        text: m.group(1),
        style: TextStyle(backgroundColor: p.warmSoft, fontWeight: FontWeight.w700, color: p.ink),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: serif(context, size: 13.5, color: p.inkSoft, height: 1.45),
    );
  }
}

// ============================================================ O'quv yo'li
class _PathPanel extends StatelessWidget {
  const _PathPanel({
    required this.chapters,
    required this.sections,
    required this.quiz,
    required this.expanded,
    required this.currentChapterId,
    required this.currentSectionId,
    required this.view,
    required this.onToggle,
    required this.onSection,
    required this.onView,
  });
  final List<Chapter> chapters;
  final Map<int, List<Section>> sections;
  final Map<int, QuizAttempt?> quiz;
  final Set<int> expanded;
  final int? currentChapterId;
  final int? currentSectionId;
  final ViewKind view;
  final ValueChanged<int> onToggle;
  final void Function(Chapter, Section) onSection;
  final void Function(Chapter, ViewKind) onView;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 20, 10),
            child: Eyebrow(s.t('learning_path')),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
              itemCount: chapters.length,
              itemBuilder: (ctx, ci) => _chapter(ctx, chapters[ci]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapter(BuildContext context, Chapter c) {
    final s = context.s;
    final p = context.pal;
    final secs = sections[c.id] ?? const <Section>[];
    final done = secs.where((x) => x.completed).length;
    final frac = secs.isEmpty ? 0.0 : done / secs.length;
    final open = expanded.contains(c.id);
    final current = c.id == currentChapterId;
    final q = quiz[c.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Hoverable(
            onTap: () => onToggle(c.id),
            radius: 14,
            color: current ? p.surface : null,
            hoverColor: p.surface,
            border: current ? p.border : null,
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
            child: Row(
              children: [
                ProgressRing(
                  value: frac,
                  size: 34,
                  stroke: 3,
                  color: frac >= 1 ? p.success : p.accent,
                  child: frac >= 1
                      ? Icon(Icons.check_rounded, size: 16, color: p.success)
                      : Text('${c.idx + 1}',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.3)),
                      const SizedBox(height: 2),
                      Text('$done / ${secs.length} ${s.t('parts_word')}',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded, color: p.muted, size: 20),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 10, top: 2),
                  child: Column(
                    children: [
                      for (var i = 0; i < secs.length; i++)
                        _node(
                          context,
                          first: i == 0,
                          last: false,
                          state: secs[i].completed
                              ? _NodeState.done
                              : (secs[i].id == currentSectionId ? _NodeState.current : _NodeState.todo),
                          selected: secs[i].id == currentSectionId,
                          eyebrow: s.t('part', {'n': i + 1}),
                          title: secs[i].lessonTitle,
                          onTap: () => onSection(c, secs[i]),
                        ),
                      _node(
                        context,
                        first: false,
                        last: false,
                        milestone: Icons.forum_outlined,
                        state: _NodeState.todo,
                        selected: current && view == ViewKind.qa,
                        title: s.t('review_qa'),
                        onTap: () => onView(c, ViewKind.qa),
                      ),
                      _node(
                        context,
                        first: false,
                        last: false,
                        milestone: Icons.quiz_outlined,
                        state: q == null ? _NodeState.todo : _NodeState.done,
                        selected: current && view == ViewKind.quiz,
                        title: s.t('review_quiz'),
                        trailing: q == null ? null : '${q.score}/${q.total}',
                        onTap: () => onView(c, ViewKind.quiz),
                      ),
                      _node(
                        context,
                        first: false,
                        last: true,
                        milestone: Icons.edit_note_rounded,
                        state: _NodeState.todo,
                        selected: current && view == ViewKind.exercises,
                        title: s.t('review_exercises'),
                        onTap: () => onView(c, ViewKind.exercises),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _node(
    BuildContext context, {
    required bool first,
    required bool last,
    required _NodeState state,
    required bool selected,
    String? eyebrow,
    String? title,
    String? trailing,
    IconData? milestone,
    required VoidCallback onTap,
  }) {
    final p = context.pal;
    final Color nodeColor = switch (state) {
      _NodeState.done => p.success,
      _NodeState.current => p.accent,
      _NodeState.todo => p.border,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: first ? 18 : 0,
                  bottom: last ? null : 0,
                  height: last ? 18 : null,
                  child: Container(width: 2, color: p.border),
                ),
                Positioned(
                  top: 10,
                  child: milestone != null
                      ? Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: state == _NodeState.done ? p.successSoft : p.surface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: state == _NodeState.done ? p.success : p.muted.withValues(alpha: 0.5),
                                width: 1.5),
                          ),
                          child: Icon(milestone,
                              size: 11, color: state == _NodeState.done ? p.success : p.muted),
                        )
                      : Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: state == _NodeState.todo ? p.surfaceAlt : nodeColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: state == _NodeState.todo ? p.muted.withValues(alpha: 0.5) : nodeColor,
                                width: 2),
                            boxShadow: state == _NodeState.current
                                ? [BoxShadow(color: p.accent.withValues(alpha: 0.35), blurRadius: 8)]
                                : null,
                          ),
                          child: state == _NodeState.done
                              ? const Icon(Icons.check_rounded, size: 10, color: Colors.white)
                              : null,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Hoverable(
                onTap: onTap,
                radius: 10,
                color: selected ? p.accentSoft : null,
                hoverColor: selected ? p.accentSoft : p.surface,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eyebrow != null)
                            Text(eyebrow,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: selected ? p.accent : p.muted)),
                          if (title != null)
                            Text(title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  fontWeight: milestone != null ? FontWeight.w600 : FontWeight.w500,
                                  color: selected ? p.ink : p.inkSoft,
                                )),
                        ],
                      ),
                    ),
                    if (trailing != null)
                      Text(trailing,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.success)),
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

enum _NodeState { done, current, todo }
