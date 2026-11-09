// Logotipni PNG fayllarga eksport qiladi (ikonka va installer uchun).
// Ishga tushirish: LOGO_OUT=<papka> flutter test test/export_logo_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:learner/widgets/logo.dart';
import 'package:path/path.dart' as p;

Future<void> _export(String dir, int px, {bool background = true, String? name}) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  LogoPainter(background: background).paint(canvas, ui.Size(px.toDouble(), px.toDouble()));
  final img = await rec.endRecording().toImage(px, px);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(p.join(dir, name ?? 'logo_$px.png')).writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  final out = Platform.environment['LOGO_OUT'];
  test('export logo', () async {
    Directory(out!).createSync(recursive: true);
    for (final s in [16, 20, 24, 32, 40, 48, 64, 128, 256, 512, 1024]) {
      await _export(out, s);
    }
  }, skip: out == null ? 'LOGO_OUT berilmagan' : false);
}
