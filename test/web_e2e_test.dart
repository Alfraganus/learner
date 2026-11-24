// Veb-manbadan o'rganishni haqiqiy sayt va `claude -p` bilan tekshirish: import → bob → dars (vizual bloklar bilan).
// Ishga tushirish: WEB_URL=<havola> WEB_SCOPE=page|section WEB_DATA=<papka> flutter test test/web_e2e_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learner/db/app_database.dart';
import 'package:learner/db/repository.dart';
import 'package:learner/models/models.dart';
import 'package:learner/services/book_processor.dart';
import 'package:learner/services/claude_service.dart';
import 'package:learner/services/content_service.dart';
import 'package:learner/services/rag_service.dart';
import 'package:learner/widgets/viz_view.dart';
import 'package:path/path.dart' as p;

void main() {
  final url = Platform.environment['WEB_URL'];
  final scope = Platform.environment['WEB_SCOPE'] ?? 'page';
  final dataDir = Platform.environment['WEB_DATA'];

  test('web source end to end', () async {
    final db = await AppDatabase.open(dir: dataDir);
    final repo = Repository(db);
    final claude = ClaudeService(workDir: p.join(dataDir!, 'claude_work'))
      ..model = 'sonnet'
      // ignore: avoid_print
      ..log = (m) => print('[${DateTime.now().toIso8601String().substring(11, 19)}] $m');
    final rag = RagService(repo);
    final processor = BookProcessor(repo, claude, rag, () {})..langProvider = () => 'uz';
    final content = ContentService(repo, claude, rag);

    final id = await processor.importUrl(url!, scope, null);
    await Future.delayed(const Duration(milliseconds: 200));
    while (processor.isActive(id)) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final book = (await repo.book(id))!;
    // ignore: avoid_print
    print('status=${book.status} msg=${book.statusMessage} title=${book.title} pages=${book.pageCount} kind=${book.sourceKind}');
    expect(book.status, BookStatus.ready);
    expect(book.isWeb, isTrue);
    final chapters = await repo.chapters(id, 'uz');
    for (final c in chapters) {
      // ignore: avoid_print
      print('chapter ${c.idx}: ${c.displayTitle} p${c.startPage}-${c.endPage}');
    }
    final secs = await repo.sections(chapters.first.id, 'uz');
    final lesson = await content.lesson(
        book: book, chapter: chapters.first, chapterSections: secs, section: secs.first, lang: 'uz');
    final vizCount = splitViz(lesson.content).where((p) => p.viz != null).length;
    // ignore: avoid_print
    print('lesson "${lesson.title}" chars=${lesson.content.length} viz=$vizCount');
    await File(p.join(dataDir, 'lesson.md')).writeAsString(lesson.content);
    expect(lesson.content.length, greaterThan(500));
    await db.db.close();
  }, timeout: const Timeout(Duration(minutes: 30)), skip: url == null || dataDir == null);
}
