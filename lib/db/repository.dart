import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/models.dart';
import 'app_database.dart';

/// Barcha SQL so'rovlar shu yerda. So'rovlar indekslarga mos yozilgan.
class Repository {
  Repository(this.appDb);
  final AppDatabase appDb;
  Database get db => appDb.db;

  // ---------------- Sozlamalar ----------------
  Future<String?> getSetting(String key) async {
    final r = await db.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------------- Kategoriyalar ----------------
  Future<List<Category>> categories() async {
    final rows = await db.rawQuery('''
      SELECT c.id, c.name,
             (SELECT COUNT(*) FROM books b WHERE b.category_id = c.id) AS book_count
      FROM categories c
      ORDER BY c.sort_order, c.name''');
    return rows.map(Category.fromRow).toList();
  }

  Future<int> addCategory(String name) =>
      db.insert('categories', {'name': name.trim(), 'created_at': nowMs()});

  Future<void> renameCategory(int id, String name) => db.update(
      'categories', {'name': name.trim()},
      where: 'id = ?', whereArgs: [id]);

  Future<void> deleteCategory(int id) =>
      db.delete('categories', where: 'id = ?', whereArgs: [id]);

  // ---------------- Kitoblar ----------------
  static const _bookSelect = '''
    SELECT b.*,
      (SELECT COUNT(*) FROM sections s WHERE s.book_id = b.id) AS total_sections,
      (SELECT COUNT(*) FROM section_progress sp WHERE sp.book_id = b.id) AS done_sections
    FROM books b''';

  /// [categoryId] == null -> barcha kitoblar; -1 -> kategoriyasizlar.
  Future<List<Book>> books({int? categoryId}) async {
    final List<Map<String, Object?>> rows;
    if (categoryId == null) {
      rows = await db.rawQuery(
          '$_bookSelect ORDER BY b.last_opened_at IS NULL, b.last_opened_at DESC, b.created_at DESC');
    } else if (categoryId == -1) {
      rows = await db.rawQuery(
          '$_bookSelect WHERE b.category_id IS NULL ORDER BY b.last_opened_at IS NULL, b.last_opened_at DESC, b.created_at DESC');
    } else {
      rows = await db.rawQuery(
          '$_bookSelect WHERE b.category_id = ? ORDER BY b.last_opened_at IS NULL, b.last_opened_at DESC, b.created_at DESC',
          [categoryId]);
    }
    return rows.map(Book.fromRow).toList();
  }

  Future<Book?> book(int id) async {
    final rows = await db.rawQuery('$_bookSelect WHERE b.id = ?', [id]);
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  /// Oxirgi ochilgan kitob ("Davom ettirish" uchun).
  Future<Book?> lastOpenedBook() async {
    final rows = await db.rawQuery(
        '$_bookSelect WHERE b.last_opened_at IS NOT NULL AND b.status = ? ORDER BY b.last_opened_at DESC LIMIT 1',
        [BookStatus.ready]);
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  Future<int> insertBook({
    required int? categoryId,
    required String title,
    required String filePath,
    required String fileName,
  }) =>
      db.insert('books', {
        'category_id': categoryId,
        'title': title,
        'file_path': filePath,
        'file_name': fileName,
        'status': BookStatus.processing,
        'created_at': nowMs(),
      });

  Future<void> updateBook(int id, Map<String, Object?> values) =>
      db.update('books', values, where: 'id = ?', whereArgs: [id]);

  Future<void> setBookStatus(int id, String status, [String? message]) =>
      updateBook(id, {'status': status, 'status_message': message});

  Future<void> deleteBook(int id) =>
      db.delete('books', where: 'id = ?', whereArgs: [id]);

  Future<List<int>> booksWithStatus(String status) async {
    final rows = await db.query('books',
        columns: ['id'], where: 'status = ?', whereArgs: [status]);
    return rows.map((r) => r['id'] as int).toList();
  }

  Future<void> savePosition(int bookId,
      {int? chapterId, int? sectionId, String? view, double? scroll}) {
    return updateBook(bookId, {
      'last_opened_at': nowMs(),
      'last_chapter_id': chapterId,
      'last_section_id': sectionId,
      'last_view': view,
      'last_scroll': scroll,
    });
  }

  Future<void> saveScroll(int bookId, double scroll) =>
      updateBook(bookId, {'last_scroll': scroll});

  // ---------------- Sahifalar ----------------
  Future<void> insertPages(int bookId, List<String> pages) async {
    await db.transaction((txn) async {
      await txn.delete('book_pages', where: 'book_id = ?', whereArgs: [bookId]);
      final batch = txn.batch();
      for (var i = 0; i < pages.length; i++) {
        batch.insert('book_pages',
            {'book_id': bookId, 'page_no': i + 1, 'text': pages[i]});
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<String>> pages(int bookId) async {
    final rows = await db.query('book_pages',
        columns: ['text'],
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'page_no');
    return rows.map((r) => r['text'] as String).toList();
  }

  /// Matni hali pdfium bilan yangilanmagan tayyor kitoblar.
  Future<List<int>> booksWithOldText() async {
    final rows = await db.query('books', columns: ['id'], where: "status = 'ready' AND text_v < 2");
    return rows.map((r) => r['id'] as int).toList();
  }

  Future<void> setTextVersion(int bookId, int v) =>
      db.update('books', {'text_v': v}, where: 'id = ?', whereArgs: [bookId]);

  /// Bob chegaralari va har bobdagi qismlar (id va asl matn, tartib bilan).
  Future<List<({int start, int end, List<({int id, String text})> sections})>> chapterLayout(int bookId) async {
    final chs = await db.query('chapters',
        columns: ['id', 'start_page', 'end_page'], where: 'book_id = ?', whereArgs: [bookId], orderBy: 'idx');
    final secs = await db.query('sections',
        columns: ['id', 'chapter_id', 'source_text'],
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'chapter_id, idx');
    return [
      for (final c in chs)
        (
          start: c['start_page'] as int,
          end: c['end_page'] as int,
          sections: [
            for (final s in secs)
              if (s['chapter_id'] == c['id']) (id: s['id'] as int, text: s['source_text'] as String),
          ],
        ),
    ];
  }

  /// Sahifalar va qismlar matnini almashtirish (tuzilma, darslar va progress o'zgarmaydi).
  Future<void> replaceBookText(
    int bookId,
    List<String> pages,
    List<({int id, int start, int end, String text, int words})> sections,
  ) async {
    await db.transaction((txn) async {
      await txn.delete('book_pages', where: 'book_id = ?', whereArgs: [bookId]);
      final batch = txn.batch();
      for (var i = 0; i < pages.length; i++) {
        batch.insert('book_pages', {'book_id': bookId, 'page_no': i + 1, 'text': pages[i]});
      }
      for (final s in sections) {
        batch.update(
            'sections',
            {'start_page': s.start, 'end_page': s.end, 'source_text': s.text, 'word_count': s.words},
            where: 'id = ?',
            whereArgs: [s.id]);
      }
      batch.update('books', {'text_v': 2}, where: 'id = ?', whereArgs: [bookId]);
      await batch.commit(noResult: true);
    });
  }

  // ---------------- Rasmlar ----------------
  Future<void> replaceFigures(int bookId, List<BookFigure> figs) async {
    await db.transaction((txn) async {
      await txn.delete('figures', where: 'book_id = ?', whereArgs: [bookId]);
      final batch = txn.batch();
      for (final f in figs) {
        batch.insert('figures', {
          'book_id': bookId,
          'label': f.label,
          'page': f.page,
          'x0': f.x0,
          'y0': f.y0,
          'x1': f.x1,
          'y1': f.y1,
        });
      }
      batch.update('books', {'figures_done': 1}, where: 'id = ?', whereArgs: [bookId]);
      await batch.commit(noResult: true);
    });
  }

  Future<List<BookFigure>> figures(int bookId) async {
    final rows = await db.query('figures',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'page, y0');
    return rows.map(BookFigure.fromRow).toList();
  }

  /// Rasmlari hali aniqlanmagan tayyor kitoblar.
  Future<List<int>> booksWithoutFigures() async {
    final rows = await db.query('books',
        columns: ['id'], where: "status = 'ready' AND figures_done = 0");
    return rows.map((r) => r['id'] as int).toList();
  }

  // ---------------- Boblar va qismlar ----------------
  /// Bob va qismlarni bitta tranzaksiyada saqlash.
  Future<List<int>> replaceStructure(
    int bookId,
    List<({String title, int start, int end, List<({int start, int end, String text, int words})> sections})>
        chapters,
  ) async {
    final ids = <int>[];
    await db.transaction((txn) async {
      await txn.delete('chapters', where: 'book_id = ?', whereArgs: [bookId]);
      for (var i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        final chId = await txn.insert('chapters', {
          'book_id': bookId,
          'idx': i,
          'title': ch.title,
          'start_page': ch.start,
          'end_page': ch.end,
        });
        ids.add(chId);
        final batch = txn.batch();
        for (var j = 0; j < ch.sections.length; j++) {
          final s = ch.sections[j];
          batch.insert('sections', {
            'chapter_id': chId,
            'book_id': bookId,
            'idx': j,
            'start_page': s.start,
            'end_page': s.end,
            'source_text': s.text,
            'word_count': s.words,
          });
        }
        await batch.commit(noResult: true);
      }
    });
    return ids;
  }

  Future<List<Chapter>> chapters(int bookId, String lang) async {
    final rows = await db.rawQuery('''
      SELECT c.*, t.title AS local_title
      FROM chapters c
      LEFT JOIN chapter_titles t ON t.chapter_id = c.id AND t.lang = ?
      WHERE c.book_id = ?
      ORDER BY c.idx''', [lang, bookId]);
    return rows.map(Chapter.fromRow).toList();
  }

  Future<void> saveChapterTitles(String lang, Map<int, String> titles) async {
    final batch = db.batch();
    titles.forEach((id, title) {
      batch.insert('chapter_titles',
          {'chapter_id': id, 'lang': lang, 'title': title},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  Future<List<Section>> sections(int chapterId, String lang) async {
    final rows = await db.rawQuery('''
      SELECT s.id, s.chapter_id, s.book_id, s.idx, s.start_page, s.end_page, s.word_count,
             l.title AS lesson_title, p.completed_at
      FROM sections s
      LEFT JOIN lessons l ON l.section_id = s.id AND l.lang = ?
      LEFT JOIN section_progress p ON p.section_id = s.id
      WHERE s.chapter_id = ?
      ORDER BY s.idx''', [lang, chapterId]);
    return rows.map(Section.fromRow).toList();
  }

  Future<List<Section>> bookSections(int bookId, String lang) async {
    final rows = await db.rawQuery('''
      SELECT s.id, s.chapter_id, s.book_id, s.idx, s.start_page, s.end_page, s.word_count,
             l.title AS lesson_title, p.completed_at
      FROM sections s
      JOIN chapters c ON c.id = s.chapter_id
      LEFT JOIN lessons l ON l.section_id = s.id AND l.lang = ?
      LEFT JOIN section_progress p ON p.section_id = s.id
      WHERE s.book_id = ?
      ORDER BY c.idx, s.idx''', [lang, bookId]);
    return rows.map(Section.fromRow).toList();
  }

  Future<String> sectionSource(int sectionId) async {
    final r = await db.query('sections',
        columns: ['source_text'], where: 'id = ?', whereArgs: [sectionId]);
    return r.isEmpty ? '' : r.first['source_text'] as String;
  }

  Future<String> chapterSource(int chapterId) async {
    final rows = await db.query('sections',
        columns: ['source_text'],
        where: 'chapter_id = ?',
        whereArgs: [chapterId],
        orderBy: 'idx');
    return rows.map((r) => r['source_text'] as String).join('\n\n');
  }

  // ---------------- Darslar ----------------
  Future<Lesson?> lesson(int sectionId, String lang) async {
    final r = await db.query('lessons',
        where: 'section_id = ? AND lang = ?', whereArgs: [sectionId, lang]);
    return r.isEmpty ? null : Lesson.fromRow(r.first);
  }

  Future<void> saveLesson(Lesson l) => db.insert(
      'lessons',
      {
        'section_id': l.sectionId,
        'lang': l.lang,
        'title': l.title,
        'content': l.content,
        'key_points': jsonEncode(l.keyPoints),
        'terms': jsonEncode(l.terms.map((t) => t.toJson()).toList()),
        'created_at': nowMs(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteLesson(int sectionId, String lang) => db.delete('lessons',
      where: 'section_id = ? AND lang = ?', whereArgs: [sectionId, lang]);

  /// Bobdagi barcha darslar (bob yakuni materiallari uchun).
  Future<List<Lesson>> chapterLessons(int chapterId, String lang) async {
    final rows = await db.rawQuery('''
      SELECT l.* FROM sections s
      JOIN lessons l ON l.section_id = s.id AND l.lang = ?
      WHERE s.chapter_id = ?
      ORDER BY s.idx''', [lang, chapterId]);
    return rows.map(Lesson.fromRow).toList();
  }

  // ---------------- Progress ----------------
  Future<void> markSectionDone(Section s) => db.insert(
      'section_progress',
      {
        'section_id': s.id,
        'book_id': s.bookId,
        'chapter_id': s.chapterId,
        'completed_at': nowMs(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> unmarkSection(int sectionId) => db.delete('section_progress',
      where: 'section_id = ?', whereArgs: [sectionId]);

  // ---------------- Bob yakuni ----------------
  Future<dynamic> review(int chapterId, String lang, String kind) async {
    final r = await db.query('chapter_reviews',
        columns: ['data'],
        where: 'chapter_id = ? AND lang = ? AND kind = ?',
        whereArgs: [chapterId, lang, kind]);
    return r.isEmpty ? null : jsonDecode(r.first['data'] as String);
  }

  Future<void> saveReview(int chapterId, String lang, String kind, Object data) =>
      db.insert(
          'chapter_reviews',
          {
            'chapter_id': chapterId,
            'lang': lang,
            'kind': kind,
            'data': jsonEncode(data),
            'created_at': nowMs(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteReview(int chapterId, String lang, String kind) =>
      db.delete('chapter_reviews',
          where: 'chapter_id = ? AND lang = ? AND kind = ?',
          whereArgs: [chapterId, lang, kind]);

  Future<void> saveQuizAttempt({
    required int chapterId,
    required int bookId,
    required String lang,
    required int score,
    required int total,
    required List<int?> answers,
  }) =>
      db.insert('quiz_attempts', {
        'chapter_id': chapterId,
        'book_id': bookId,
        'lang': lang,
        'score': score,
        'total': total,
        'answers': jsonEncode(answers),
        'created_at': nowMs(),
      });

  Future<QuizAttempt?> bestQuizAttempt(int chapterId) async {
    final r = await db.query('quiz_attempts',
        columns: ['score', 'total', 'created_at'],
        where: 'chapter_id = ?',
        whereArgs: [chapterId],
        orderBy: 'created_at DESC',
        limit: 1);
    if (r.isEmpty) return null;
    return QuizAttempt(r.first['score'] as int, r.first['total'] as int,
        r.first['created_at'] as int);
  }

  Future<Map<int, ExerciseAnswer>> exerciseAnswers(
      int chapterId, String lang) async {
    final rows = await db.query('exercise_answers',
        where: 'chapter_id = ? AND lang = ?', whereArgs: [chapterId, lang]);
    return {
      for (final r in rows)
        r['exercise_idx'] as int: ExerciseAnswer(
          index: r['exercise_idx'] as int,
          answer: r['answer'] as String,
          feedback: r['feedback'] as String?,
          score: r['score'] as int?,
        )
    };
  }

  Future<void> saveExerciseAnswer(int chapterId, String lang, int idx,
          String answer, String? feedback, int? score) =>
      db.insert(
          'exercise_answers',
          {
            'chapter_id': chapterId,
            'lang': lang,
            'exercise_idx': idx,
            'answer': answer,
            'feedback': feedback,
            'score': score,
            'updated_at': nowMs(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------------- Chat ----------------
  Future<List<ChatMessage>> chat(int bookId, {int limit = 200}) async {
    final rows = await db.rawQuery('''
      SELECT * FROM (
        SELECT * FROM chat_messages WHERE book_id = ? ORDER BY id DESC LIMIT ?
      ) ORDER BY id''', [bookId, limit]);
    return rows.map(ChatMessage.fromRow).toList();
  }

  Future<int> addChat(int bookId, String role, String content,
          {int? chapterId, int? sectionId, String? sources}) =>
      db.insert('chat_messages', {
        'book_id': bookId,
        'chapter_id': chapterId,
        'section_id': sectionId,
        'role': role,
        'content': content,
        'sources': sources,
        'created_at': nowMs(),
      });

  /// "Davom ettirish" kartasi uchun: kitobdagi joriy joy.
  Future<({int chapterIdx, String chapterTitle, int? sectionIdx, int sectionCount, String? lessonTitle})?>
      position(Book b, String lang) async {
    if (b.lastChapterId == null) return null;
    final r = await db.rawQuery('''
      SELECT c.idx, COALESCE(t.title, c.title) AS title,
             (SELECT COUNT(*) FROM sections x WHERE x.chapter_id = c.id) AS cnt,
             s.idx AS sidx, l.title AS ltitle
      FROM chapters c
      LEFT JOIN chapter_titles t ON t.chapter_id = c.id AND t.lang = ?
      LEFT JOIN sections s ON s.id = ?
      LEFT JOIN lessons l ON l.section_id = s.id AND l.lang = ?
      WHERE c.id = ?''', [lang, b.lastSectionId, lang, b.lastChapterId]);
    if (r.isEmpty) return null;
    final x = r.first;
    return (
      chapterIdx: x['idx'] as int,
      chapterTitle: x['title'] as String,
      sectionIdx: x['sidx'] as int?,
      sectionCount: x['cnt'] as int,
      lessonTitle: x['ltitle'] as String?,
    );
  }

  // ---------------- Statistika ----------------
  Future<LearningStats> stats() async {
    final books = _firstInt(await db.rawQuery('SELECT COUNT(*) FROM books')) ?? 0;
    final total = _firstInt(await db.rawQuery('SELECT COUNT(*) FROM sections')) ?? 0;
    final done =
        _firstInt(await db.rawQuery('SELECT COUNT(*) FROM section_progress')) ?? 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 60));
    final rows = await db.rawQuery(
        'SELECT completed_at FROM section_progress WHERE completed_at >= ?',
        [weekStart.millisecondsSinceEpoch]);
    final perDay = <int, int>{};
    for (final r in rows) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['completed_at'] as int);
      final key = DateTime(d.year, d.month, d.day).difference(today).inDays; // 0, -1, -2...
      perDay[key] = (perDay[key] ?? 0) + 1;
    }
    var streak = 0;
    var day = (perDay[0] ?? 0) > 0 ? 0 : -1; // bugun hali o'qimagan bo'lsa, kechadan sanaymiz
    while ((perDay[day] ?? 0) > 0) {
      streak++;
      day--;
    }
    final quiz = await db.rawQuery(
        'SELECT AVG(CAST(score AS REAL) / total) AS a FROM quiz_attempts WHERE total > 0');
    return LearningStats(
      books: books,
      sectionsDone: done,
      sectionsTotal: total,
      doneToday: perDay[0] ?? 0,
      streak: streak,
      quizAvg: (quiz.first['a'] as num?)?.toDouble(),
      week: [for (var i = -6; i <= 0; i++) perDay[i] ?? 0],
    );
  }

  Future<void> clearChat(int bookId) =>
      db.delete('chat_messages', where: 'book_id = ?', whereArgs: [bookId]);
}

int? _firstInt(List<Map<String, Object?>> rows) =>
    rows.isEmpty || rows.first.isEmpty ? null : (rows.first.values.first as num?)?.toInt();
