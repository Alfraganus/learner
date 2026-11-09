import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:learner/db/app_database.dart';
import 'package:learner/db/repository.dart';
import 'package:learner/models/models.dart';
import 'package:learner/services/book_processor.dart';
import 'package:learner/services/chunker.dart';
import 'package:learner/services/claude_service.dart';
import 'package:learner/services/content_service.dart';
import 'package:learner/services/pdf_service.dart';
import 'package:learner/services/rag_service.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' show pdfrxInitialize;
import 'package:syncfusion_flutter_pdf/pdf.dart';

const _ch1 = [
  'Chapter 1. What is HTTP',
  'HTTP (Hypertext Transfer Protocol) is the protocol browsers and servers use to talk. '
      'A client sends a request and the server returns a response. Every request has a method, '
      'a path, headers and an optional body. The most common methods are GET, POST, PUT and DELETE. '
      'GET reads data and must not change anything on the server. POST creates new data.',
  'HTTP is stateless: the server does not remember previous requests. To keep a user logged in, '
      'applications use cookies or tokens that the client sends with every request. '
      'Example: GET /users/42 HTTP/1.1 with header Accept: application/json asks for user 42 as JSON.',
];
const _ch2 = [
  'Chapter 2. Status codes',
  'Every response has a three-digit status code. 2xx codes mean success: 200 OK, 201 Created. '
      '3xx codes are redirects such as 301 Moved Permanently. 4xx codes are client errors: '
      '400 Bad Request, 401 Unauthorized, 404 Not Found. 5xx codes are server errors like 500.',
  'A good API returns precise codes. For example, creating a resource should return 201 with a '
      'Location header. Returning 200 for every error makes clients harder to write, because they '
      'must parse the body to detect failures. Retry only on 5xx and 429 Too Many Requests.',
];

Future<String> _makePdf(String dir) async {
  final doc = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  final big = PdfStandardFont(PdfFontFamily.helvetica, 22, style: PdfFontStyle.bold);
  void page(String text, {bool title = false}) {
    final pg = doc.pages.add();
    pg.graphics.drawString(text, title ? big : font,
        bounds: Rect.fromLTWH(0, 0, pg.getClientSize().width, pg.getClientSize().height));
  }

  page('HTTP for Beginners\n\nby Test Author', title: true);
  page('Contents\n\nChapter 1. What is HTTP ........ 3\nChapter 2. Status codes ........ 5');
  for (final ch in [_ch1, _ch2]) {
    page('${ch[0]}\n\n${ch[1]}');
    page(ch[2]);
  }
  final path = p.join(dir, 'http_beginners.pdf');
  await File(path).writeAsBytes(await doc.save());
  doc.dispose();
  return path;
}

void main() {
  test('chunker keeps every line', () {
    final pages = [
      for (var i = 1; i <= 6; i++)
        (page: i, text: List.generate(60, (j) => 'Line $i.$j has some words here.').join('\n')),
    ];
    final chunks = chunkPages(pages, targetWords: 500, maxWords: 800);
    final joined = chunks.map((c) => c.text).join('\n');
    for (var i = 1; i <= 6; i++) {
      for (var j = 0; j < 60; j++) {
        expect(joined.contains('Line $i.$j has'), isTrue);
      }
    }
    expect(chunks.length, greaterThan(1));
  });

  test('API structured schema is made strict', () {
    final s = ClaudeService.strictSchema({
      'type': 'object',
      'properties': {
        'a': {'type': 'string'},
        'list': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {'x': {'type': 'integer'}},
          },
        },
      },
      'required': ['a'],
    });
    expect(s['additionalProperties'], false);
    expect(s['required'], ['a', 'list']);
    final item = (s['properties'] as Map)['list']['items'] as Map;
    expect(item['additionalProperties'], false);
    expect(item['required'], ['x']);
    expect(ClaudeService.apiModelId('sonnet'), 'claude-sonnet-5-5');
  });

  test('FTS query builder', () {
    expect(RagService.buildQuery(['GET va POST farqi nima?']), contains('"post"*'));
    expect(RagService.buildQuery(['?? !!']), isNull);
  });

  test('v1 database upgrades to latest (v4) and gets indexed', () async {
    final src = Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .where((d) => p.basename(d.path).startsWith('learner_test') &&
            File(p.join(d.path, 'learner.db')).existsSync())
        .toList();
    final v1 = src.where((d) {
      // faqat eski (v1) bazalar
      return !File(p.join(d.path, 'v2.marker')).existsSync();
    }).toList();
    if (v1.isEmpty) return;
    final tmp = await Directory.systemTemp.createTemp('learner_upgrade');
    for (final f in ['learner.db', 'learner.db-wal', 'learner.db-shm']) {
      final from = File(p.join(v1.first.path, f));
      if (from.existsSync()) await from.copy(p.join(tmp.path, f));
    }
    final db = await AppDatabase.open(dir: tmp.path);
    final version = (await db.db.rawQuery('PRAGMA user_version')).first.values.first;
    expect(version, 4);
    // v3: rasmlar jadvali va kitobdagi belgi. v4: matn versiyasi.
    await db.db.rawQuery('SELECT figures_done, text_v FROM books LIMIT 1');
    await db.db.rawQuery('SELECT COUNT(*) FROM figures');
    final rag = RagService(Repository(db));
    await rag.backfill();
    final cnt = (await db.db.rawQuery('SELECT COUNT(*) c FROM rag_chunks')).first['c'] as int;
    // ignore: avoid_print
    print('upgraded ${v1.first.path}: rag_chunks=$cnt');
    await db.db.close();
  });

  test('pdfium text: new extraction and refresh of old books', () async {
    PdfService.initEngine = pdfrxInitialize;
    final tmp = await Directory.systemTemp.createTemp('learner_text');
    final pdf = await _makePdf(tmp.path);

    final fresh = await PdfService.pdfiumPages(pdf);
    expect(fresh, isNotNull);
    expect(fresh![2], contains('HTTP (Hypertext Transfer Protocol)'));
    final ex = await PdfService.extract(pdf);
    expect(ex.pages[2], fresh[2]);
    expect(ex.outline, isEmpty);
    expect(PdfService.cleanPdfiumText('back-of-the-envelope\u0002calculations\r\nnext'),
        'back-of-the-envelope-calculations\nnext');

    // Eski import: syncfusion "buzgan" matn, bitta bob (3-4 sahifalar) va bitta qism.
    final db = await AppDatabase.open(dir: tmp.path);
    final repo = Repository(db);
    final bookId = await repo.insertBook(categoryId: null, title: 'HTTP', filePath: pdf, fileName: 'h.pdf');
    // syncfusion xatolariga o'xshash: ortiqcha "y" va yopishgan qatorlar.
    final broken = [for (final t in fresh) t.replaceAll('the', 'thye').replaceAll('\n', '')];
    await repo.insertPages(bookId, broken);
    await repo.replaceStructure(bookId, [
      // 1-bob: ikki qism, chegara 3- va 4-sahifa orasida.
      (title: 'Ch1', start: 3, end: 4, sections: [
        (start: 3, end: 3, text: broken[2], words: 70),
        (start: 4, end: 4, text: broken[3], words: 50),
      ]),
      // 2-bob: matni PDF ga mos kelmaydi -> o'zgarmasdan qoladi.
      (title: 'Ch2', start: 5, end: 6, sections: [(start: 5, end: 6, text: 'something else entirely', words: 3)]),
    ]);
    await repo.setBookStatus(bookId, BookStatus.ready, null);
    expect(await repo.booksWithOldText(), [bookId]);
    final idsBefore = (await db.db.query('sections', where: 'book_id = ?', whereArgs: [bookId], orderBy: 'id'))
        .map((r) => r['id'])
        .toList();

    final processor = BookProcessor(repo, ClaudeService(workDir: p.join(tmp.path, 'w')), RagService(repo), () {});
    final r = await processor.refreshText(bookId);
    expect(r, (updated: 1, total: 2));
    final after = await db.db.query('sections', where: 'book_id = ?', whereArgs: [bookId], orderBy: 'id');
    expect(after.map((r) => r['id']).toList(), idsBefore);
    final a = after[0]['source_text'] as String, b = after[1]['source_text'] as String;
    expect(a, contains('HTTP (Hypertext Transfer Protocol)'));
    expect(a, contains('POST creates new data.'));
    expect(a, isNot(contains('thye')));
    expect(a, isNot(contains('stateless')));
    expect(b, startsWith('HTTP is stateless'));
    expect(after[2]['source_text'], 'something else entirely');
    expect((await repo.pages(bookId))[3], fresh[3]);
    expect(await repo.booksWithOldText(), isEmpty);
    final rag = (await db.db.rawQuery("SELECT text FROM rag_chunks WHERE book_id = ? AND kind = 'source'", [bookId]));
    expect(rag.map((e) => e['text']).join(' '), contains('stateless'));
    await db.db.close();
  });

  test('full pipeline with claude -p', () async {
    final tmp = await Directory.systemTemp.createTemp('learner_test');
    await File(p.join(tmp.path, 'v2.marker')).writeAsString('v2');
    final pdf = await _makePdf(tmp.path);

    final ex = await PdfService.extract(pdf);
    expect(ex.pages.length, 6);
    expect(ex.pages[2], contains('What is HTTP'));

    final db = await AppDatabase.open(dir: tmp.path);
    final repo = Repository(db);
    final claude = ClaudeService(workDir: p.join(tmp.path, 'work'))..model = 'haiku'
      // ignore: avoid_print
      ..log = (m) => print('[${DateTime.now().toIso8601String().substring(11, 19)}] $m');
    final rag = RagService(repo);
    final processor = BookProcessor(repo, claude, rag, () {})..langProvider = () => 'uz';
    final content = ContentService(repo, claude, rag);

    final catId = await repo.addCategory('IT');
    final bookId = await processor.importPdf(pdf, catId);
    while (processor.isActive(bookId)) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    final book = (await repo.book(bookId))!;
    // ignore: avoid_print
    print('status=${book.status} msg=${book.statusMessage} title=${book.title} lang=${book.sourceLang}');
    expect(book.status, BookStatus.ready);

    final chapters = await repo.chapters(bookId, 'uz');
    for (final c in chapters) {
      // ignore: avoid_print
      print('chapter ${c.idx}: "${c.title}" / "${c.localTitle}" pages ${c.startPage}-${c.endPage}');
    }
    expect(chapters.length, 2);
    expect(chapters.first.startPage, 3);

    final books = await repo.books(categoryId: catId);
    expect(books.single.totalSections, greaterThanOrEqualTo(2));

    final secs = await repo.sections(chapters.first.id, 'uz');
    final lesson = await content.lesson(
        book: book, chapter: chapters.first, chapterSections: secs, section: secs.first, lang: 'uz');
    // ignore: avoid_print
    print('--- LESSON: ${lesson.title}\n${lesson.content}\nKEY: ${lesson.keyPoints}');
    expect(lesson.content.length, greaterThan(100));

    final quiz = await content.quiz(book, chapters.first, 'uz');
    // ignore: avoid_print
    print('--- QUIZ[0]: ${quiz.first.question} ${quiz.first.options} -> ${quiz.first.correctIndex}');
    expect(quiz.length, greaterThanOrEqualTo(5));

    await repo.markSectionDone(secs.first);
    await repo.savePosition(bookId, chapterId: chapters.first.id, sectionId: secs.first.id, view: 'lesson');
    final last = await repo.lastOpenedBook();
    expect(last?.id, bookId);
    expect(last?.doneSections, 1);

    // RAG: kitob matni indekslangan, inglizcha qidiruv 2-bobni topadi.
    final hits = await rag.search(bookId, ['404 Not Found status code'], lang: 'uz');
    // ignore: avoid_print
    print('--- RAG hits: ${hits.map((h) => '${h.chapterIdx}/${h.sectionIdx} p${h.pageStart} ${h.snippet}').toList()}');
    expect(hits, isNotEmpty);
    expect(hits.first.chapterIdx, 1);
    // Dars ham (o'zbekcha) indekslangan.
    final lessonHits = await rag.search(bookId, [lesson.keyPoints.first], lang: 'uz');
    expect(lessonHits.any((h) => h.kind == 'lesson'), isTrue);

    // Savol o'zbekcha, kitob inglizcha va javob 2-bobda: manba 2-bobni ko'rsatishi kerak.
    final r = await content.ask(
        book: book,
        chapter: chapters.first,
        section: secs.first,
        question: '404 kodi nimani bildiradi va qachon qayta urinish kerak?',
        lang: 'uz');
    // ignore: avoid_print
    print('--- ASK: ${r.answer}\nSOURCES:${r.sources.map((x) => '[${x.n}] ch${x.chapterIdx + 1} part${x.sectionIdx + 1} p${x.pages}').toList()}');
    expect(r.answer, isNotEmpty);
    expect(r.sources.any((x) => x.chapterId == chapters[1].id), isTrue);
    final chat = await repo.chat(bookId);
    expect(chat.length, 2);
    expect(chat.last.sourcesJson, isNotNull);
    expect(SourceRef.listFromJson(chat.last.sourcesJson), isNotEmpty);

    await db.db.close();
  }, timeout: const Timeout(Duration(minutes: 15)), skip: Platform.environment['RUN_CLAUDE'] != '1');
}
