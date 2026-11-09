import 'dart:async';
import 'dart:convert';

import '../db/repository.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'claude_service.dart';
import 'prompts.dart';
import 'rag_service.dart';

/// Darslar, bob yakuni materiallari va savol-javobni yaratadi.
/// Natijalar SQLite'da keshlanadi; bir xil so'rov ikki marta yuborilmaydi.
class ContentService {
  ContentService(this.repo, this.claude, this.rag);

  final Repository repo;
  final ClaudeService claude;
  final RagService rag;
  final _inflight = <String, Future<dynamic>>{};

  Future<T> _once<T>(String key, Future<T> Function() fn) {
    final existing = _inflight[key];
    if (existing != null) return existing as Future<T>;
    final f = fn().whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = f;
    return f;
  }

  bool isGenerating(String key) => _inflight.containsKey(key);

  static String lessonKey(int sectionId, String lang) => 'lesson:$sectionId:$lang';

  // ---------------- Dars ----------------
  Future<Lesson> lesson({
    required Book book,
    required Chapter chapter,
    required List<Section> chapterSections,
    required Section section,
    required String lang,
    bool force = false,
    bool background = false,
  }) {
    return _once(lessonKey(section.id, lang), () async {
      if (!force) {
        final cached = await repo.lesson(section.id, lang);
        if (cached != null) return cached;
      }
      final source = await repo.sectionSource(section.id);
      String? prevTitle;
      final i = chapterSections.indexWhere((s) => s.id == section.id);
      if (i > 0) prevTitle = (await repo.lesson(chapterSections[i - 1].id, lang))?.title;

      final r = await claude.structured(
        system: Prompts.teacherSystem(lang),
        prompt: Prompts.lessonPrompt(
          bookTitle: book.title,
          chapterTitle: chapter.title,
          partNo: section.idx + 1,
          partCount: chapterSections.length,
          previousTitle: prevTitle,
          source: source,
        ),
        schema: Prompts.lessonSchema,
        background: background,
      );
      final lesson = Lesson(
        sectionId: section.id,
        lang: lang,
        title: '${r['title'] ?? ''}'.trim(),
        content: '${r['content'] ?? ''}'.trim(),
        keyPoints: ((r['key_points'] as List?) ?? []).map((e) => '$e').toList(),
        terms: ((r['terms'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Term.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
      if (lesson.content.isEmpty) throw ClaudeException(S.ui.t('err_empty'));
      await repo.saveLesson(lesson);
      try {
        await rag.indexLesson(lesson);
      } catch (_) {}
      return lesson;
    });
  }

  /// Keyingi qismni oldindan tayyorlab qo'yish (foydalanuvchi kutmasligi uchun).
  void prefetch({
    required Book book,
    required Chapter chapter,
    required List<Section> chapterSections,
    required Section section,
    required String lang,
  }) {
    unawaited(() async {
      try {
        if (await repo.lesson(section.id, lang) != null) return;
        await lesson(
            book: book,
            chapter: chapter,
            chapterSections: chapterSections,
            section: section,
            lang: lang,
            background: true);
      } catch (_) {}
    }());
  }

  /// Bob yakuni materiallarini oldindan tayyorlash.
  void prefetchReviews(Book book, Chapter chapter, String lang) {
    for (final f in [
      () => qa(book, chapter, lang, background: true),
      () => quiz(book, chapter, lang, background: true),
      () => exercises(book, chapter, lang, background: true),
    ]) {
      unawaited(f().then((_) {}, onError: (_) {}));
    }
  }

  // ---------------- Bob yakuni ----------------
  Future<String> _chapterMaterial(Chapter chapter, String lang) async {
    const limit = 220000;
    final source = await repo.chapterSource(chapter.id);
    if (source.length <= limit) return source;
    final lessons = await repo.chapterLessons(chapter.id, lang);
    final joined = lessons.map((l) => '## ${l.title}\n${l.content}').join('\n\n');
    if (lessons.isNotEmpty && joined.length <= limit) return joined;
    return source.substring(0, limit);
  }

  Future<List<QaItem>> qa(Book book, Chapter chapter, String lang, {bool force = false, bool background = false}) =>
      _once('qa:${chapter.id}:$lang', () async {
        if (!force) {
          final c = await repo.review(chapter.id, lang, 'qa');
          if (c != null) return _parseQa(c);
        }
        final r = await claude.structured(
          system: Prompts.teacherSystem(lang),
          prompt: Prompts.qaPrompt(book.title, chapter.title, await _chapterMaterial(chapter, lang)),
          schema: Prompts.qaSchema,
          background: background,
        );
        await repo.saveReview(chapter.id, lang, 'qa', r);
        return _parseQa(r);
      });

  List<QaItem> _parseQa(dynamic d) => ((d['items'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => QaItem.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  Future<List<QuizQuestion>> quiz(Book book, Chapter chapter, String lang, {bool force = false, bool background = false}) =>
      _once('quiz:${chapter.id}:$lang', () async {
        if (!force) {
          final c = await repo.review(chapter.id, lang, 'quiz');
          if (c != null) return _parseQuiz(c);
        }
        final r = await claude.structured(
          system: Prompts.teacherSystem(lang),
          prompt: Prompts.quizPrompt(book.title, chapter.title, await _chapterMaterial(chapter, lang)),
          schema: Prompts.quizSchema,
          background: background,
        );
        await repo.saveReview(chapter.id, lang, 'quiz', r);
        return _parseQuiz(r);
      });

  List<QuizQuestion> _parseQuiz(dynamic d) => ((d['questions'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e)))
      .where((q) =>
          q.options.length >= 2 && q.correctIndex >= 0 && q.correctIndex < q.options.length)
      .toList();

  Future<List<Exercise>> exercises(Book book, Chapter chapter, String lang,
          {bool force = false, bool background = false}) =>
      _once('ex:${chapter.id}:$lang', () async {
        if (!force) {
          final c = await repo.review(chapter.id, lang, 'exercises');
          if (c != null) return _parseEx(c);
        }
        final r = await claude.structured(
          system: Prompts.teacherSystem(lang),
          prompt: Prompts.exercisesPrompt(
              book.title, chapter.title, await _chapterMaterial(chapter, lang)),
          schema: Prompts.exercisesSchema,
          background: background,
        );
        await repo.saveReview(chapter.id, lang, 'exercises', r);
        return _parseEx(r);
      });

  List<Exercise> _parseEx(dynamic d) => ((d['exercises'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => Exercise.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  Future<({int score, String feedback})> checkExercise({
    required Chapter chapter,
    required Exercise exercise,
    required int index,
    required String answer,
    required String lang,
  }) async {
    final r = await claude.structured(
      system: Prompts.teacherSystem(lang),
      prompt: Prompts.checkExercisePrompt(
        chapter: chapter.displayTitle,
        task: exercise.task,
        solution: exercise.solution,
        answer: answer,
      ),
      schema: Prompts.checkSchema,
    );
    final score = ((r['score'] as num?)?.toInt() ?? 0).clamp(0, 100);
    final feedback = '${r['feedback'] ?? ''}'.trim();
    await repo.saveExerciseAnswer(chapter.id, lang, index, answer, feedback, score);
    return (score: score, feedback: feedback);
  }

  // ---------------- Savol berish (RAG) ----------------
  /// Savolga kitob asosida javob: FTS5 (bm25) bilan tegishli bo'laklar topiladi,
  /// Claude ularga tayanib javob beradi va [n] ko'rinishida manbani ko'rsatadi.
  Future<({String answer, List<SourceRef> sources})> ask({
    required Book book,
    required Chapter? chapter,
    required Section? section,
    required String question,
    required String lang,
    void Function(String textSoFar)? onDelta,
  }) async {
    final history = await repo.chat(book.id, limit: 10);
    await repo.addChat(book.id, 'user', question, chapterId: chapter?.id, sectionId: section?.id);

    // 1) Qidiruv: avval savolning o'zi bilan.
    var hits = await rag.search(book.id, [question],
        lang: lang, currentChapterId: chapter?.id, currentSectionId: section?.id);
    final bookLang = (book.sourceLang ?? '').toLowerCase();
    final crossLang = bookLang.isNotEmpty && !bookLang.startsWith(lang);
    if (crossLang || hits.length < 4) {
      // 2) Kitob tilidagi kalit so'zlar bilan kengaytirish (tez model).
      try {
        final r = await claude.structured(
          system: 'You turn learner questions into search keywords for a full-text index. '
              'Answer only via structured output.',
          prompt: Prompts.searchTermsPrompt(
            question: question,
            bookTitle: book.title,
            bookLang: bookLang.isEmpty ? 'unknown' : bookLang,
            learnerLang: lang,
            chapterTitle: chapter?.title,
          ),
          schema: Prompts.searchTermsSchema,
          fast: true,
        );
        final terms = ((r['terms'] as List?) ?? []).map((e) => '$e').toList();
        final more = await rag.search(book.id, [question, ...terms],
            lang: lang, currentChapterId: chapter?.id, currentSectionId: section?.id);
        if (more.isNotEmpty) hits = more;
      } catch (_) {}
    }

    // 3) Manbalar ro'yxati: [1] — joriy qism, keyin topilgan bo'laklar.
    final sources = <SourceRef>[];
    final blocks = <String>[];
    final chapters = {for (final c in await repo.chapters(book.id, lang)) c.id: c};
    String label(int chapterIdx, String chTitle, int secIdx, String pages) =>
        'Chapter ${chapterIdx + 1} «$chTitle» › part ${secIdx + 1}, pages $pages';

    if (section != null && chapter != null) {
      var src = await repo.sectionSource(section.id);
      if (src.length > 7000) src = '${src.substring(0, 7000)}…';
      final ref = SourceRef(
        n: 1,
        chapterId: chapter.id,
        sectionId: section.id,
        chapterIdx: chapter.idx,
        sectionIdx: section.idx,
        chapterTitle: chapter.displayTitle,
        pageStart: section.startPage,
        pageEnd: section.endPage,
        kind: 'current',
      );
      sources.add(ref);
      blocks.add('[1] ${label(chapter.idx, chapter.title, section.idx, ref.pages)} — (the part the learner is reading now)\n$src');
    }
    for (final h in hits) {
      if (section != null && h.sectionId == section.id && h.kind == 'source') continue;
      final n = sources.length + 1;
      final ch = chapters[h.chapterId];
      final ref = SourceRef(
        n: n,
        chapterId: h.chapterId,
        sectionId: h.sectionId,
        chapterIdx: h.chapterIdx,
        sectionIdx: h.sectionIdx,
        chapterTitle: ch?.displayTitle ?? h.chapterTitle,
        pageStart: h.pageStart,
        pageEnd: h.pageEnd,
        snippet: h.snippet,
        kind: h.kind,
      );
      sources.add(ref);
      blocks.add('[$n] ${label(h.chapterIdx, h.chapterTitle, h.sectionIdx, ref.pages)}'
          '${h.kind == 'lesson' ? ' (from the simplified lesson)' : ''}\n${h.text}');
      if (sources.length >= 9) break;
    }

    // 4) Javob
    final answer = await claude.text(
      system: Prompts.teacherSystem(lang),
      prompt: Prompts.askRagPrompt(
        bookTitle: book.title,
        chapterTitle: chapter?.title,
        sources: blocks,
        history: [for (final m in history) (role: m.role, content: m.content)],
        question: question,
        lang: lang,
      ),
      onDelta: onDelta,
    );

    // 5) Javobda tilga olingan manbalarni saqlaymiz.
    final cited = RegExp(r'\[(\d+)\]').allMatches(answer).map((m) => int.parse(m.group(1)!)).toSet();
    final used = sources.where((s) => cited.contains(s.n)).toList();
    await repo.addChat(book.id, 'assistant', answer,
        chapterId: chapter?.id,
        sectionId: section?.id,
        sources: jsonEncode(used.map((e) => e.toJson()).toList()));
    return (answer: answer, sources: used);
  }

  /// Kitob ichidan tezkor qidiruv (Claude'siz, faqat FTS5).
  Future<List<RagHit>> searchBook(int bookId, String query, String lang) =>
      rag.search(bookId, [query], lang: lang, limit: 20, perSection: 1);

  // ---------------- Bob nomlari tarjimasi ----------------
  Future<void> ensureChapterTitles(int bookId, String lang) =>
      _once('titles:$bookId:$lang', () async {
        final chapters = await repo.chapters(bookId, lang);
        final missing = chapters.where((c) => c.localTitle == null).toList();
        if (missing.isEmpty) return;
        final r = await claude.structured(
          system: 'You are a precise translator. Answer only via structured output.',
          prompt: Prompts.translateTitlesPrompt(missing.map((c) => c.title).toList(), lang),
          schema: Prompts.translateTitlesSchema,
          background: true,
          fast: true,
        );
        final list = ((r['titles'] as List?) ?? []).map((e) => '$e'.trim()).toList();
        final map = <int, String>{};
        for (var i = 0; i < missing.length && i < list.length; i++) {
          if (list[i].isNotEmpty) map[missing[i].id] = list[i];
        }
        await repo.saveChapterTitles(lang, map);
      });
}
