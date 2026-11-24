// Yangi bo'limlar skrinshotlari (vizual tekshiruv uchun).
// IV_DATA — intervyu e2e testi bazasi, WEB_DATA — veb e2e testi bazasi, SHOTS_OUT — chiqish papkasi.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learner/db/interview_repo.dart';
import 'package:learner/screens/interview_screen.dart';
import 'package:learner/screens/interviews_page.dart';
import 'package:learner/screens/lesson_view.dart';
import 'package:learner/state/app_state.dart';
import 'package:learner/ui/theme.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final file = File(f);
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
}

Future<void> _fonts() async {
  const w = r'C:\Windows\Fonts';
  final segoe = ['segoeui.ttf', 'segoeuib.ttf', 'seguisb.ttf'].map((f) => '$w\\$f').toList();
  await _loadFont('Segoe UI Variable Text', segoe);
  await _loadFont('Segoe UI Variable Display', segoe);
  await _loadFont('Georgia', ['$w\\georgia.ttf', '$w\\georgiab.ttf', '$w\\georgiai.ttf']);
  await _loadFont('Consolas', ['$w\\consola.ttf', '$w\\consolab.ttf']);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter';
  await _loadFont('MaterialIcons',
      [p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf')]);
}

Future<Directory> _copy(String src) async {
  final t = await Directory.systemTemp.createTemp('learner_fshot');
  for (final e in Directory(src).listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: src);
    if (rel.startsWith('claude_work')) continue;
    final dst = File(p.join(t.path, rel));
    await dst.parent.create(recursive: true);
    await e.copy(dst.path);
  }
  return t;
}

void main() {
  final out = Platform.environment['SHOTS_OUT'];
  final ivData = Platform.environment['IV_DATA'];
  final webData = Platform.environment['WEB_DATA'];

  Future<void> shot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File(p.join(out!, '$name.png')).writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> settle(WidgetTester tester, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('interview screens', (tester) async {
    await tester.runAsync(_fonts);
    final tmp = (await tester.runAsync(() => _copy(ivData!)))!;
    final state = (await tester.runAsync(() => AppState.create(dataDir: tmp.path, background: false)))!;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(1300, 800);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: InterviewsPage())),
      ),
    ));
    await settle(tester);
    await shot(tester, 'interviews_list');

    // Belgilar: 2-savolga izoh va parcha, 4-savol shunchaki muhim.
    await tester.runAsync(() async {
      final ivId = state.interviews.first.id;
      final items = await state.repo.interviewItems(ivId);
      await state.repo.updateItemMarks(items[1].id,
          starred: true,
          note: "Stack bilan yechimni yana bir bor yozib ko'rish kerak",
          highlights: [items[1].keyPoints.isNotEmpty ? items[1].keyPoints.first : items[1].text]);
      if (items.length > 3) await state.repo.updateItemMarks(items[3].id, starred: true);
      await state.refresh();
    });

    tester.view.physicalSize = const Size(1200, 9000);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: InterviewScreen(interviewId: state.interviews.first.id),
        ),
      ),
    ));
    await settle(tester, 30);
    await shot(tester, 'interview_detail');
  }, skip: out == null || ivData == null);

  testWidgets('web lesson with visuals', (tester) async {
    await tester.runAsync(_fonts);
    final tmp = (await tester.runAsync(() => _copy(webData!)))!;
    final state = (await tester.runAsync(() => AppState.create(dataDir: tmp.path, background: false)))!;
    final book = (await tester.runAsync(() => state.repo.book(state.allBooks.first.id)))!;
    final chapters = (await tester.runAsync(() => state.repo.chapters(book.id, 'uz')))!;
    final sections = (await tester.runAsync(() => state.repo.sections(chapters.first.id, 'uz')))!;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 9000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: LessonView(
              book: book,
              chapter: chapters.first,
              sections: sections,
              section: sections.first,
              initialScroll: 0,
              onScroll: (_) {},
              onPrev: null,
              onNext: () {},
            ),
          ),
        ),
      ),
    ));
    await settle(tester, 30);
    await shot(tester, 'web_lesson');
  }, skip: out == null || webData == null);
}
