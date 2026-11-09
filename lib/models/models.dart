import 'dart:convert';

int nowMs() => DateTime.now().millisecondsSinceEpoch;

class Category {
  Category({required this.id, required this.name, this.bookCount = 0});
  final int id;
  final String name;
  final int bookCount;

  factory Category.fromRow(Map<String, Object?> r) => Category(
        id: r['id'] as int,
        name: r['name'] as String,
        bookCount: (r['book_count'] as int?) ?? 0,
      );
}

class BookStatus {
  static const processing = 'processing';
  static const ready = 'ready';
  static const error = 'error';
}

class Book {
  Book({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.author,
    required this.filePath,
    required this.fileName,
    required this.pageCount,
    required this.sourceLang,
    required this.status,
    required this.statusMessage,
    required this.createdAt,
    required this.lastOpenedAt,
    required this.lastChapterId,
    required this.lastSectionId,
    required this.lastView,
    required this.lastScroll,
    this.totalSections = 0,
    this.doneSections = 0,
  });

  final int id;
  final int? categoryId;
  final String title;
  final String? author;
  final String filePath;
  final String fileName;
  final int pageCount;
  final String? sourceLang;
  final String status;
  final String? statusMessage;
  final int createdAt;
  final int? lastOpenedAt;
  final int? lastChapterId;
  final int? lastSectionId;
  final String? lastView;
  final double? lastScroll;
  final int totalSections;
  final int doneSections;

  double get progress => totalSections == 0 ? 0 : doneSections / totalSections;
  bool get isReady => status == BookStatus.ready;

  factory Book.fromRow(Map<String, Object?> r) => Book(
        id: r['id'] as int,
        categoryId: r['category_id'] as int?,
        title: r['title'] as String,
        author: r['author'] as String?,
        filePath: r['file_path'] as String,
        fileName: r['file_name'] as String,
        pageCount: r['page_count'] as int,
        sourceLang: r['source_lang'] as String?,
        status: r['status'] as String,
        statusMessage: r['status_message'] as String?,
        createdAt: r['created_at'] as int,
        lastOpenedAt: r['last_opened_at'] as int?,
        lastChapterId: r['last_chapter_id'] as int?,
        lastSectionId: r['last_section_id'] as int?,
        lastView: r['last_view'] as String?,
        lastScroll: (r['last_scroll'] as num?)?.toDouble(),
        totalSections: (r['total_sections'] as int?) ?? 0,
        doneSections: (r['done_sections'] as int?) ?? 0,
      );
}

class Chapter {
  Chapter({
    required this.id,
    required this.bookId,
    required this.idx,
    required this.title,
    required this.localTitle,
    required this.startPage,
    required this.endPage,
  });
  final int id;
  final int bookId;
  final int idx;
  final String title;
  final String? localTitle;
  final int startPage;
  final int endPage;

  String get displayTitle => localTitle ?? title;

  factory Chapter.fromRow(Map<String, Object?> r) => Chapter(
        id: r['id'] as int,
        bookId: r['book_id'] as int,
        idx: r['idx'] as int,
        title: r['title'] as String,
        localTitle: r['local_title'] as String?,
        startPage: r['start_page'] as int,
        endPage: r['end_page'] as int,
      );
}

class Section {
  Section({
    required this.id,
    required this.chapterId,
    required this.bookId,
    required this.idx,
    required this.startPage,
    required this.endPage,
    required this.wordCount,
    required this.lessonTitle,
    required this.completed,
  });
  final int id;
  final int chapterId;
  final int bookId;
  final int idx;
  final int startPage;
  final int endPage;
  final int wordCount;
  final String? lessonTitle;
  final bool completed;

  factory Section.fromRow(Map<String, Object?> r) => Section(
        id: r['id'] as int,
        chapterId: r['chapter_id'] as int,
        bookId: r['book_id'] as int,
        idx: r['idx'] as int,
        startPage: r['start_page'] as int,
        endPage: r['end_page'] as int,
        wordCount: r['word_count'] as int,
        lessonTitle: r['lesson_title'] as String?,
        completed: r['completed_at'] != null,
      );
}

class Term {
  Term(this.term, this.explanation);
  final String term;
  final String explanation;
  Map<String, dynamic> toJson() => {'term': term, 'explanation': explanation};
  factory Term.fromJson(Map<String, dynamic> j) =>
      Term('${j['term'] ?? ''}', '${j['explanation'] ?? ''}');
}

class Lesson {
  Lesson({
    required this.sectionId,
    required this.lang,
    required this.title,
    required this.content,
    required this.keyPoints,
    required this.terms,
  });
  final int sectionId;
  final String lang;
  final String title;
  final String content;
  final List<String> keyPoints;
  final List<Term> terms;

  factory Lesson.fromRow(Map<String, Object?> r) => Lesson(
        sectionId: r['section_id'] as int,
        lang: r['lang'] as String,
        title: r['title'] as String,
        content: r['content'] as String,
        keyPoints: (jsonDecode(r['key_points'] as String) as List)
            .map((e) => '$e')
            .toList(),
        terms: (jsonDecode(r['terms'] as String) as List)
            .map((e) => Term.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class QaItem {
  QaItem(this.question, this.answer);
  final String question;
  final String answer;
  factory QaItem.fromJson(Map<String, dynamic> j) =>
      QaItem('${j['question'] ?? ''}', '${j['answer'] ?? ''}');
}

class QuizQuestion {
  QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
        question: '${j['question'] ?? ''}',
        options: ((j['options'] as List?) ?? []).map((e) => '$e').toList(),
        correctIndex: (j['correct_index'] as num?)?.toInt() ?? 0,
        explanation: '${j['explanation'] ?? ''}',
      );
}

class Exercise {
  Exercise({
    required this.title,
    required this.task,
    required this.hint,
    required this.solution,
    required this.difficulty,
  });
  final String title;
  final String task;
  final String hint;
  final String solution;
  final String difficulty;

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        title: '${j['title'] ?? ''}',
        task: '${j['task'] ?? ''}',
        hint: '${j['hint'] ?? ''}',
        solution: '${j['solution'] ?? ''}',
        difficulty: '${j['difficulty'] ?? ''}',
      );
}

class ExerciseAnswer {
  ExerciseAnswer({
    required this.index,
    required this.answer,
    required this.feedback,
    required this.score,
  });
  final int index;
  final String answer;
  final String? feedback;
  final int? score;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.chapterId,
    required this.sectionId,
    required this.createdAt,
    this.sourcesJson,
  });
  final int id;
  final String role; // 'user' | 'assistant'
  final String content;
  final int? chapterId;
  final int? sectionId;
  final int createdAt;

  /// Javob tayangan manbalar (JSON, [SourceRef] ro'yxati).
  final String? sourcesJson;

  bool get isUser => role == 'user';

  factory ChatMessage.fromRow(Map<String, Object?> r) => ChatMessage(
        id: r['id'] as int,
        role: r['role'] as String,
        content: r['content'] as String,
        chapterId: r['chapter_id'] as int?,
        sectionId: r['section_id'] as int?,
        createdAt: r['created_at'] as int,
        sourcesJson: r['sources'] as String?,
      );
}

class QuizAttempt {
  QuizAttempt(this.score, this.total, this.createdAt);
  final int score;
  final int total;
  final int createdAt;
}

/// Boblarni ajratish natijasi.
class ChapterPlan {
  ChapterPlan(this.title, this.startPage, this.include);
  final String title;
  final int startPage; // 1-based
  final bool include;
}

/// Bosh sahifa statistikasi.
class LearningStats {
  LearningStats({
    required this.books,
    required this.sectionsDone,
    required this.sectionsTotal,
    required this.doneToday,
    required this.streak,
    required this.quizAvg,
    required this.week,
  });
  final int books;
  final int sectionsDone;
  final int sectionsTotal;
  final int doneToday;
  final int streak;
  final double? quizAvg;

  /// Oxirgi 7 kun (eskidan yangiga) — har kuni o'rganilgan qismlar soni.
  final List<int> week;
}

/// Kitobdagi rasm: [label] — "1-4" ko'rinishida, koordinatalar sahifaga nisbatan 0..1 (yuqori-chap).
class BookFigure {
  const BookFigure({
    required this.label,
    required this.page,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });
  final String label;
  final int page;
  final double x0, y0, x1, y1;

  factory BookFigure.fromRow(Map<String, Object?> r) => BookFigure(
        label: r['label'] as String,
        page: r['page'] as int,
        x0: (r['x0'] as num).toDouble(),
        y0: (r['y0'] as num).toDouble(),
        x1: (r['x1'] as num).toDouble(),
        y1: (r['y1'] as num).toDouble(),
      );

  @override
  String toString() => 'Figure $label p$page (${x0.toStringAsFixed(2)},${y0.toStringAsFixed(2)})-(${x1.toStringAsFixed(2)},${y1.toStringAsFixed(2)})';
}
