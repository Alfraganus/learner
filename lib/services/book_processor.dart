import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/repository.dart';
import '../models/models.dart';
import 'chunker.dart';
import 'claude_service.dart';
import 'figure_service.dart';
import 'pdf_service.dart';
import 'prompts.dart';
import 'rag_service.dart';

/// PDF ni import qilish: matn ajratish -> boblarni aniqlash (claude) -> qismlarga bo'lish.
class BookProcessor {
  BookProcessor(this.repo, this.claude, this.rag, this.onChanged);

  final Repository repo;
  final ClaudeService claude;
  final RagService rag;
  final void Function() onChanged;
  String Function() langProvider = () => 'uz';
  FigureService? figures;
  void Function()? onFiguresReady;

  final _active = <int>{};

  bool isActive(int bookId) => _active.contains(bookId);

  Future<int> importPdf(String sourcePath, int? categoryId) async {
    final booksDir = Directory(p.join(repo.appDb.dataDir.path, 'books'));
    await booksDir.create(recursive: true);
    final dest = p.join(booksDir.path, '${const Uuid().v4()}.pdf');
    await File(sourcePath).copy(dest);
    final fileName = p.basename(sourcePath);
    final id = await repo.insertBook(
      categoryId: categoryId,
      title: p.basenameWithoutExtension(sourcePath),
      filePath: dest,
      fileName: fileName,
    );
    onChanged();
    process(id);
    return id;
  }

  /// Ilova qayta ochilganda chala qolgan importlarni davom ettirish.
  Future<void> resumePending() async {
    for (final id in await repo.booksWithStatus(BookStatus.processing)) {
      process(id);
    }
  }

  Future<void> process(int bookId) async {
    if (_active.contains(bookId)) return;
    _active.add(bookId);
    try {
      await _process(bookId);
    } on ClaudeException catch (e) {
      await repo.setBookStatus(bookId, BookStatus.error, e.message);
    } catch (e) {
      await repo.setBookStatus(bookId, BookStatus.error, '$e');
    } finally {
      _active.remove(bookId);
      onChanged();
    }
  }

  Future<void> _step(int bookId, String key) async {
    await repo.setBookStatus(bookId, BookStatus.processing, key);
    onChanged();
  }

  Future<void> _process(int bookId) async {
    final book = await repo.book(bookId);
    if (book == null) return;
    final lang = langProvider();

    // 1) Matnni ajratish
    await _step(bookId, 'step_extract');
    final ex = await PdfService.extract(book.filePath);
    if (ex.totalChars < 200) {
      await repo.setBookStatus(bookId, BookStatus.error, 'no_text');
      return;
    }
    await repo.insertPages(bookId, ex.pages);
    await repo.updateBook(bookId, {
      'page_count': ex.pages.length,
      if (ex.title != null && ex.title!.length > 2) 'title': ex.title,
      if (ex.author != null) 'author': ex.author,
    });
    onChanged();

    // 2) Boblarni aniqlash
    await _step(bookId, 'step_structure');
    final digest = _digest(ex);
    final res = await claude.structured(
      system: Prompts.structureSystem,
      prompt: Prompts.structurePrompt(
        fileName: book.fileName,
        pageCount: ex.pages.length,
        outline: digest.outline,
        frontText: digest.front,
        pageHeads: digest.heads,
        targetLang: lang,
      ),
      schema: Prompts.structureSchema,
    );

    final title = '${res['title'] ?? ''}'.trim();
    final author = '${res['author'] ?? ''}'.trim();
    final language = '${res['language'] ?? ''}'.trim();
    await repo.updateBook(bookId, {
      if (title.isNotEmpty) 'title': title,
      if (author.isNotEmpty) 'author': author,
      if (language.isNotEmpty) 'source_lang': language,
    });

    final plans = <({ChapterPlan plan, String local})>[];
    for (final c in (res['chapters'] as List? ?? const [])) {
      if (c is! Map) continue;
      final start = (c['start_page'] as num?)?.toInt() ?? 0;
      if (start < 1 || start > ex.pages.length) continue;
      plans.add((
        plan: ChapterPlan('${c['title'] ?? ''}'.trim(), start, c['include'] != false),
        local: '${c['title_local'] ?? ''}'.trim(),
      ));
    }
    plans.sort((a, b) => a.plan.startPage.compareTo(b.plan.startPage));
    // Bir xil sahifadan boshlanganlarni birlashtirish
    final uniq = <({ChapterPlan plan, String local})>[];
    for (final pl in plans) {
      if (uniq.isNotEmpty && uniq.last.plan.startPage == pl.plan.startPage) continue;
      uniq.add(pl);
    }

    // 3) Qismlarga bo'lish
    await _step(bookId, 'step_split');
    final chapters = <({String title, int start, int end, List<({int start, int end, String text, int words})> sections})>[];
    final localTitles = <String>[];

    void addChapter(String title, String local, int start, int end) {
      final pages = [
        for (var pg = start; pg <= end; pg++) (page: pg, text: ex.pages[pg - 1]),
      ];
      final chunks = chunkPages(pages);
      final words = chunks.fold<int>(0, (a, c) => a + c.words);
      if (words < 40) return; // amalda bo'sh sahifalar (bo'lim sarlavhasi va h.k.)
      chapters.add((
        title: title.isEmpty ? 'Chapter ${chapters.length + 1}' : title,
        start: start,
        end: end,
        sections: [
          for (final c in chunks)
            (start: c.startPage, end: c.endPage, text: c.text, words: c.words),
        ],
      ));
      localTitles.add(local);
    }

    if (uniq.isEmpty) {
      // Zaxira: har 15 sahifani bitta bo'lim qilamiz.
      const step = 15;
      for (var s = 1; s <= ex.pages.length; s += step) {
        final e = (s + step - 1).clamp(1, ex.pages.length);
        addChapter('Pages $s–$e', '', s, e);
      }
    } else {
      for (var i = 0; i < uniq.length; i++) {
        final cur = uniq[i];
        final end = i + 1 < uniq.length ? uniq[i + 1].plan.startPage - 1 : ex.pages.length;
        if (!cur.plan.include || end < cur.plan.startPage) continue;
        addChapter(cur.plan.title, cur.local, cur.plan.startPage, end);
      }
    }

    if (chapters.isEmpty) {
      await repo.setBookStatus(bookId, BookStatus.error, 'no_text');
      return;
    }

    final ids = await repo.replaceStructure(bookId, chapters);
    final titles = <int, String>{};
    for (var i = 0; i < ids.length; i++) {
      if (localTitles[i].isNotEmpty) titles[ids[i]] = localTitles[i];
    }
    if (titles.isNotEmpty) await repo.saveChapterTitles(lang, titles);

    // 4) RAG indeksi (savollarga kitobdan javob topish uchun)
    await _step(bookId, 'step_index');
    await rag.indexBookSource(bookId);

    // 5) Rasmlar (darsda "1-4-rasm" havolasi turgan joyda ko'rsatish uchun). Xato bo'lsa — kitob baribir tayyor.
    if (figures != null) {
      await _step(bookId, 'step_figures');
      try {
        await figures!.detectBook(bookId);
        onFiguresReady?.call();
      } catch (_) {}
    }

    await repo.setBookStatus(bookId, BookStatus.ready, null);
  }

  ({String outline, String front, String heads}) _digest(PdfExtraction ex) {
    final outline = ex.outline.isEmpty
        ? '(none)'
        : ex.outline
            .map((o) => '${'  ' * o.level}- ${o.title}  → [p ${o.page}]')
            .join('\n');

    final front = StringBuffer();
    for (var i = 0; i < ex.pages.length && front.length < 16000; i++) {
      front.writeln('[p ${i + 1}]');
      front.writeln(ex.pages[i]);
    }

    // Har sahifaning boshidagi qatorlar. Juda katta kitoblarda qisqaroq.
    final perPage = ex.pages.length > 800 ? 110 : (ex.pages.length > 400 ? 160 : 240);
    final heads = StringBuffer();
    for (var i = 0; i < ex.pages.length; i++) {
      final lines = ex.pages[i]
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .take(4)
          .join(' | ');
      final cut = lines.length > perPage ? '${lines.substring(0, perPage)}…' : lines;
      heads.writeln('[p ${i + 1}] ${cut.isEmpty ? '(blank)' : cut}');
    }

    var frontStr = front.toString();
    if (frontStr.length > 16000) frontStr = frontStr.substring(0, 16000);
    return (outline: outline, front: frontStr, heads: heads.toString());
  }
}
