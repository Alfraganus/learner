import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/repository.dart';
import '../models/models.dart';

/// Javob/qidiruv natijasining kitobdagi joyi.
class SourceRef {
  SourceRef({
    required this.n,
    required this.chapterId,
    required this.sectionId,
    required this.chapterIdx,
    required this.sectionIdx,
    required this.chapterTitle,
    required this.pageStart,
    required this.pageEnd,
    this.snippet = '',
    this.kind = 'source',
  });

  final int n;
  final int chapterId;
  final int sectionId;
  final int chapterIdx;
  final int sectionIdx;
  final String chapterTitle;
  final int pageStart;
  final int pageEnd;
  final String snippet;
  final String kind;

  String get pages => pageStart == pageEnd ? '$pageStart' : '$pageStart–$pageEnd';

  Map<String, dynamic> toJson() => {
        'n': n,
        'chapter_id': chapterId,
        'section_id': sectionId,
        'chapter_idx': chapterIdx,
        'section_idx': sectionIdx,
        'chapter_title': chapterTitle,
        'page_start': pageStart,
        'page_end': pageEnd,
        'snippet': snippet,
        'kind': kind,
      };

  factory SourceRef.fromJson(Map<String, dynamic> j) => SourceRef(
        n: (j['n'] as num?)?.toInt() ?? 0,
        chapterId: (j['chapter_id'] as num).toInt(),
        sectionId: (j['section_id'] as num).toInt(),
        chapterIdx: (j['chapter_idx'] as num?)?.toInt() ?? 0,
        sectionIdx: (j['section_idx'] as num?)?.toInt() ?? 0,
        chapterTitle: '${j['chapter_title'] ?? ''}',
        pageStart: (j['page_start'] as num?)?.toInt() ?? 0,
        pageEnd: (j['page_end'] as num?)?.toInt() ?? 0,
        snippet: '${j['snippet'] ?? ''}',
        kind: '${j['kind'] ?? 'source'}',
      );

  static List<SourceRef> listFromJson(String? s) {
    if (s == null || s.isEmpty) return const [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => SourceRef.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class RagHit {
  RagHit({
    required this.chunkId,
    required this.chapterId,
    required this.sectionId,
    required this.chapterIdx,
    required this.sectionIdx,
    required this.chapterTitle,
    required this.localTitle,
    required this.kind,
    required this.pageStart,
    required this.pageEnd,
    required this.text,
    required this.snippet,
    required this.score,
  });
  final int chunkId;
  final int chapterId;
  final int sectionId;
  final int chapterIdx;
  final int sectionIdx;
  final String chapterTitle;
  final String? localTitle;
  final String kind;
  final int pageStart;
  final int pageEnd;
  final String text;
  final String snippet;
  double score;
}

/// Kitob bo'yicha RAG: matnni kichik bo'laklarga bo'lib SQLite FTS5 da indekslaydi,
/// bm25 bo'yicha qidiradi va har bir topilmaning bob/qism/sahifasini qaytaradi.
class RagService {
  RagService(this.repo);
  final Repository repo;
  Database get db => repo.db;

  static const _chunkWords = 200;
  static const _overlapWords = 40;

  /// Matnni ~200 so'zlik, bir-biriga biroz kiradigan bo'laklarga bo'lish.
  /// Sahifa raqami bo'lakning matndagi o'rniga qarab taxminlanadi.
  static List<({String text, int pageStart, int pageEnd})> split(
      String text, int startPage, int endPage) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final out = <({String text, int pageStart, int pageEnd})>[];
    final pages = (endPage - startPage + 1).clamp(1, 100000);
    int pageAt(int i) => startPage + ((i / words.length) * pages).floor().clamp(0, pages - 1);
    for (var i = 0; i < words.length; i += _chunkWords - _overlapWords) {
      final end = (i + _chunkWords).clamp(0, words.length);
      out.add((
        text: words.sublist(i, end).join(' '),
        pageStart: pageAt(i),
        pageEnd: pageAt(end - 1),
      ));
      if (end == words.length) break;
    }
    return out;
  }

  // ---------------- Indekslash ----------------
  /// Kitobning asl matnini (barcha qismlarni) indekslash.
  Future<void> indexBookSource(int bookId) async {
    final sections = await db.query('sections',
        columns: ['id', 'chapter_id', 'start_page', 'end_page', 'source_text'],
        where: 'book_id = ?',
        whereArgs: [bookId]);
    await db.transaction((txn) async {
      await txn.delete('rag_chunks',
          where: 'book_id = ? AND kind = ?', whereArgs: [bookId, 'source']);
      final batch = txn.batch();
      for (final s in sections) {
        final parts = split(s['source_text'] as String, s['start_page'] as int, s['end_page'] as int);
        for (var i = 0; i < parts.length; i++) {
          batch.insert('rag_chunks', {
            'book_id': bookId,
            'chapter_id': s['chapter_id'],
            'section_id': s['id'],
            'kind': 'source',
            'lang': '',
            'seq': i,
            'page_start': parts[i].pageStart,
            'page_end': parts[i].pageEnd,
            'text': parts[i].text,
          });
        }
      }
      await batch.commit(noResult: true);
    });
  }

  /// Soddalashtirilgan darsni indekslash (foydalanuvchi tilida qidirish uchun).
  Future<void> indexLesson(Lesson lesson) async {
    final s = await db.query('sections',
        columns: ['book_id', 'chapter_id', 'start_page', 'end_page'],
        where: 'id = ?',
        whereArgs: [lesson.sectionId]);
    if (s.isEmpty) return;
    final sec = s.first;
    final body = [
      lesson.title,
      lesson.content,
      ...lesson.keyPoints,
      ...lesson.terms.map((t) => '${t.term} — ${t.explanation}'),
    ].join('\n');
    final parts = split(body, sec['start_page'] as int, sec['end_page'] as int);
    await db.transaction((txn) async {
      await txn.delete('rag_chunks',
          where: 'section_id = ? AND kind = ? AND lang = ?',
          whereArgs: [lesson.sectionId, 'lesson', lesson.lang]);
      final batch = txn.batch();
      for (var i = 0; i < parts.length; i++) {
        batch.insert('rag_chunks', {
          'book_id': sec['book_id'],
          'chapter_id': sec['chapter_id'],
          'section_id': lesson.sectionId,
          'kind': 'lesson',
          'lang': lesson.lang,
          'seq': i,
          'page_start': parts[i].pageStart,
          'page_end': parts[i].pageEnd,
          'text': parts[i].text,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// Eski (v1) ma'lumotlarni indekslash: indekssiz kitoblar va darslar.
  Future<void> backfill() async {
    final books = await db.rawQuery('''
      SELECT b.id FROM books b
      WHERE b.status = 'ready'
        AND NOT EXISTS (SELECT 1 FROM rag_chunks r WHERE r.book_id = b.id AND r.kind = 'source')''');
    for (final b in books) {
      await indexBookSource(b['id'] as int);
    }
    final lessons = await db.rawQuery('''
      SELECT l.* FROM lessons l
      WHERE NOT EXISTS (SELECT 1 FROM rag_chunks r
        WHERE r.section_id = l.section_id AND r.kind = 'lesson' AND r.lang = l.lang)''');
    for (final l in lessons) {
      await indexLesson(Lesson.fromRow(l));
    }
  }

  // ---------------- Qidiruv ----------------
  static final _wordRe = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’ʻ‘\-]*", unicode: true);

  /// Erkin matn yoki kalit so'zlardan FTS5 so'rovi: har bir so'z prefiks bilan, OR orqali.
  static String? buildQuery(Iterable<String> terms) {
    final parts = <String>{};
    for (final t in terms) {
      final words = _wordRe.allMatches(t.toLowerCase()).map((m) => m.group(0)!).toList();
      if (words.isEmpty) continue;
      if (words.length > 1 && words.length <= 4) {
        parts.add('"${words.join(' ').replaceAll('"', '')}"');
      }
      for (final w0 in words) {
        final w = w0.replaceAll(RegExp(r"['’ʻ‘\-]"), '');
        if (w.length < 3 || _stop.contains(w)) continue;
        // Qo'shimchalar uchun (kitoblar -> kitob*) ildizni prefiks qilamiz.
        final stem = w.length > 6 ? w.substring(0, w.length - 2) : w;
        parts.add('"$stem"*');
      }
    }
    if (parts.isEmpty) return null;
    return parts.take(40).join(' OR ');
  }

  /// bm25 bo'yicha qidiruv. Joriy bob/qismga yaqin natijalar biroz yuqoriga ko'tariladi.
  Future<List<RagHit>> search(
    int bookId,
    Iterable<String> terms, {
    required String lang,
    int limit = 8,
    int? currentChapterId,
    int? currentSectionId,
    int perSection = 2,
  }) async {
    final q = buildQuery(terms);
    if (q == null) return const [];
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery('''
        SELECT r.id, r.chapter_id, r.section_id, r.kind, r.page_start, r.page_end, r.text,
               c.idx AS chapter_idx, c.title AS chapter_title, t.title AS local_title,
               s.idx AS section_idx,
               bm25(rag_fts) AS rank,
               snippet(rag_fts, 0, '«', '»', '…', 18) AS snip
        FROM rag_fts
        JOIN rag_chunks r ON r.id = rag_fts.rowid
        JOIN chapters c ON c.id = r.chapter_id
        JOIN sections s ON s.id = r.section_id
        LEFT JOIN chapter_titles t ON t.chapter_id = c.id AND t.lang = ?
        WHERE rag_fts MATCH ? AND r.book_id = ? AND (r.kind = 'source' OR r.lang = ?)
        ORDER BY rank
        LIMIT 60''', [lang, q, bookId, lang]);
    } catch (_) {
      return const [];
    }

    final hits = rows.map((r) {
      var score = -((r['rank'] as num?)?.toDouble() ?? 0);
      if (r['section_id'] == currentSectionId) {
        score *= 1.35;
      } else if (r['chapter_id'] == currentChapterId) {
        score *= 1.15;
      }
      return RagHit(
        chunkId: r['id'] as int,
        chapterId: r['chapter_id'] as int,
        sectionId: r['section_id'] as int,
        chapterIdx: r['chapter_idx'] as int,
        sectionIdx: r['section_idx'] as int,
        chapterTitle: r['chapter_title'] as String,
        localTitle: r['local_title'] as String?,
        kind: r['kind'] as String,
        pageStart: r['page_start'] as int,
        pageEnd: r['page_end'] as int,
        text: r['text'] as String,
        snippet: (r['snip'] as String?) ?? '',
        score: score,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // Bir qismdan ko'pi bilan [perSection] ta bo'lak — natijalar xilma-xil bo'lsin.
    final perSec = <int, int>{};
    final out = <RagHit>[];
    for (final h in hits) {
      final n = perSec[h.sectionId] ?? 0;
      if (n >= perSection) continue;
      perSec[h.sectionId] = n + 1;
      out.add(h);
      if (out.length >= limit) break;
    }
    return out;
  }

  static const _stop = {
    // en
    'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'can', 'her', 'was', 'one', 'our',
    'out', 'has', 'how', 'what', 'why', 'who', 'this', 'that', 'with', 'from', 'they', 'have',
    'does', 'did', 'about', 'which', 'when', 'where', 'there', 'their', 'into', 'than', 'then',
    'explain', 'tell', 'mean', 'means',
    // uz
    'nima', 'nega', 'qanday', 'qaysi', 'qachon', 'kim', 'bu', 'shu', 'va', 'ham', 'bilan',
    'uchun', 'emas', 'edi', 'degan', 'nimaga', 'haqida', 'menga', 'tushuntir', 'tushuntiring',
    'farqi', 'nimadir', 'mumkin', 'kerak',
    // ru
    'что', 'как', 'это', 'для', 'или', 'почему', 'когда', 'где', 'кто', 'такое', 'объясни',
  };
}
