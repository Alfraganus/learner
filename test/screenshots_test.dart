// Interfeys skrinshotlari (vizual tekshiruv uchun).
// Ishga tushirish: SHOTS_OUT=<papka> flutter test test/screenshots_test.dart
// Ma'lumot sifatida pipeline testi yaratgan oxirgi bazadan nusxa olinadi.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learner/main.dart';
import 'package:learner/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  var any = false;
  for (final f in files) {
    final file = File(f);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    any = true;
  }
  if (any) await loader.load();
}

Future<void> _loadFonts() async {
  const w = r'C:\Windows\Fonts';
  final segoe = ['segoeui.ttf', 'segoeuib.ttf', 'seguisb.ttf', 'segoeuii.ttf'].map((f) => '$w\\$f').toList();
  await _loadFont('Segoe UI Variable Text', segoe);
  await _loadFont('Segoe UI Variable Display', segoe);
  await _loadFont('Segoe UI', segoe);
  await _loadFont('Georgia', ['georgia.ttf', 'georgiab.ttf', 'georgiai.ttf', 'georgiaz.ttf'].map((f) => '$w\\$f').toList());
  await _loadFont('Consolas', ['consola.ttf', 'consolab.ttf'].map((f) => '$w\\$f').toList());
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter';
  await _loadFont('MaterialIcons', [p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf')]);
}

Directory? _latestDataDir() {
  final dirs = Directory.systemTemp
      .listSync()
      .whereType<Directory>()
      .where((d) =>
          p.basename(d.path).startsWith('learner_test') &&
          File(p.join(d.path, 'v2.marker')).existsSync())
      .toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  return dirs.isEmpty ? null : dirs.first;
}

void main() {
  final out = Platform.environment['SHOTS_OUT'];

  testWidgets('screenshots', (tester) async {
    final src = _latestDataDir();
    if (src == null) return;
    await tester.runAsync(_loadFonts);

    final tmp = await tester.runAsync(() async {
      final t = await Directory.systemTemp.createTemp('learner_shots');
      for (final e in src.listSync()) {
        if (e is File) await e.copy(p.join(t.path, p.basename(e.path)));
      }
      final books = Directory(p.join(src.path, 'books'));
      if (books.existsSync()) {
        await Directory(p.join(t.path, 'books')).create();
        for (final f in books.listSync().whereType<File>()) {
          await f.copy(p.join(t.path, 'books', p.basename(f.path)));
        }
      }
      return t;
    });

    final state = (await tester.runAsync(() => AppState.create(dataDir: tmp!.path, background: false)))!;
    final view = tester.view;
    view.physicalSize = const Size(1600, 1000);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);

    Future<void> settle([int ms = 400]) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future.delayed(Duration(milliseconds: ms ~/ 3)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shot(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File(p.join(out!, '$name.png')).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.runAsync(() => state.setThemeMode(mode));
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: ChangeNotifierProvider.value(value: state, child: const LearnerApp()),
      ));
      await settle();
      await shot('home_${mode.name}');

      if (mode == ThemeMode.light) {
        // Javon
        await tester.tap(find.text('Javon').first);
        await settle();
        await shot('library_light');
        // Sozlamalar
        await tester.tap(find.text('Sozlamalar').last);
        await settle();
        await shot('settings_light');
        await tester.tap(find.text('Bugun').first);
        await settle();
      }

      // Kitobni ochish
      await tester.tap(find.text('Davom ettirish').last);
      await settle(1200);
      await settle(800);
      await shot('book_${mode.name}');

      if (mode == ThemeMode.light) {
        await tester.tap(find.text('Quiz').first);
        await settle(900);
        await shot('quiz_light');
        final opt = find.text('A');
        if (opt.evaluate().isNotEmpty) {
          await tester.tap(opt.first);
          await settle();
          await shot('quiz_answered_light');
        }
      }
      // orqaga
      await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
      await settle();
    }
  }, skip: out == null);
}
