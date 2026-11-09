// Dars sahifasidagi rasmlar skrinshoti (vizual tekshiruv uchun).
// Ishga tushirish: LESSON_DB=<learner.db papkasi> SHOTS_OUT=<papka> flutter test test/lesson_figures_shot_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learner/screens/lesson_view.dart';
import 'package:learner/services/figure_service.dart';
import 'package:learner/state/app_state.dart';
import 'package:learner/ui/theme.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final file = File(f);
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
}

void main() {
  final src = Platform.environment['LESSON_DB'];
  final out = Platform.environment['SHOTS_OUT'];

  testWidgets('lesson with figures', (tester) async {
    const w = r'C:\Windows\Fonts';
    await tester.runAsync(() async {
      await _loadFont('Segoe UI Variable Text', ['$w\\segoeui.ttf', '$w\\segoeuib.ttf', '$w\\seguisb.ttf']);
      await _loadFont('Segoe UI Variable Display', ['$w\\segoeui.ttf', '$w\\segoeuib.ttf']);
      await _loadFont('Georgia', ['$w\\georgia.ttf', '$w\\georgiab.ttf', '$w\\georgiai.ttf']);
      final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter';
      await _loadFont('MaterialIcons',
          [p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf')]);
      FigureService.initEngine = pdfrxInitialize;
      await pdfrxInitialize();
    });

    final tmp = (await tester.runAsync(() async {
      final t = await Directory.systemTemp.createTemp('learner_figshot');
      for (final f in ['learner.db', 'learner.db-wal', 'learner.db-shm']) {
        final from = File(p.join(src!, f));
        if (from.existsSync()) await from.copy(p.join(t.path, f));
      }
      return t;
    }))!;
    final state = (await tester.runAsync(() => AppState.create(dataDir: tmp.path, background: false)))!;
    final book = (await tester.runAsync(() => state.repo.book(1)))!;
    final chapters = (await tester.runAsync(() => state.repo.chapters(1, 'uz')))!;
    final ch = chapters.firstWhere((c) => c.id == 2);
    final sections = (await tester.runAsync(() => state.repo.sections(ch.id, 'uz')))!;
    final sec = sections.first;

    tester.view.physicalSize = const Size(1100, 5200);
    tester.view.devicePixelRatio = 1;
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
              chapter: ch,
              sections: sections,
              section: sec,
              initialScroll: 0,
              onScroll: (_) {},
              onPrev: null,
              onNext: () {},
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('1-4-rasm'), findsWidgets);

    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File(p.join(out!, 'lesson_figures.png')).writeAsBytes(bytes!.buffer.asUint8List());
    });
  }, skip: src == null || out == null);
}
