// Til almashtirgich: chap paneldagi globus menyusi interfeys tilini darhol o'zgartiradi,
// o'rganish tili esa alohida saqlanadi.
// SHOTS_OUT=<papka> berilsa, har bir tilda skrinshot ham saqlanadi.
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
  for (final f in files.where((f) => File(f).existsSync())) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  final out = Platform.environment['SHOTS_OUT'];

  testWidgets('globe menu switches interface language only', (tester) async {
    if (out != null) {
      await tester.runAsync(() async {
        const w = r'C:\Windows\Fonts';
        final segoe = ['segoeui.ttf', 'segoeuib.ttf', 'seguisb.ttf'].map((f) => '$w\$f').toList();
        for (final fam in ['Segoe UI Variable Text', 'Segoe UI Variable Display', 'Segoe UI']) {
          await _loadFont(fam, segoe);
        }
        await _loadFont('Georgia', ['georgia.ttf', 'georgiab.ttf'].map((f) => '$w\$f').toList());
        final root = Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter';
        await _loadFont('MaterialIcons',
            [p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf')]);
      });
    }
    final tmp = (await tester.runAsync(() => Directory.systemTemp.createTemp('learner_lang')))!;
    final state = (await tester.runAsync(() => AppState.create(dataDir: tmp.path, background: false)))!;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> shot(String name) async {
      if (out == null) return;
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      await tester.runAsync(() async {
        Directory(out).createSync(recursive: true);
        final img = await b.toImage(pixelRatio: 1.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File(p.join(out, '$name.png')).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await tester.runAsync(() => state.setThemeMode(ThemeMode.light));
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: ChangeNotifierProvider.value(value: state, child: const LearnerApp()),
    ));
    await settle();
    expect(find.text('Javon'), findsWidgets);

    Future<void> pick(String code, String label) async {
      await tester.tap(find.byIcon(Icons.language_rounded).first);
      await settle();
      await tester.tap(find.text(label).last);
      await settle();
      expect(state.uiLang, code);
    }

    await pick('ru', 'Русский');
    expect(find.text('Полка'), findsWidgets);
    expect(state.lang, 'uz', reason: 'learning language must not change');
    await shot('home_ru');
    await tester.tap(find.text('Настройки').last);
    await settle();
    await shot('settings_ru');

    await pick('en', 'English');
    expect(find.text('Interface language'), findsOneWidget);
    await shot('settings_en');
    await tester.tap(find.text('Today').first);
    await settle();
    await shot('home_en');

    await pick('uz', "O'zbekcha");
    expect(find.text('Bugun'), findsWidgets);
    await shot('home_uz');
  });
}
