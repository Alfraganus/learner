// Rasmlarni havolalarga bog'lash va darsga joylash.
// Haqiqiy PDF bilan: FIG_PDF=<kitob.pdf> flutter test test/figures_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learner/models/models.dart';
import 'package:learner/services/figure_service.dart';
import 'package:pdfrx/pdfrx.dart';

FigureCandidate c(int page, double top, {bool cap = true}) =>
    FigureCandidate(page, 0.1, top, 0.9, top + 0.3, captioned: cap);

BookFigure f(String label) =>
    BookFigure(label: label, page: 1, x0: 0, y0: 0, x1: 1, y1: 1);

void main() {
  test('assign: yozuvsiz kod rasmi tashlanadi, tilga olinmagan raqam o\'z joyini oladi', () {
    final cands = [
      c(14, 0.1), // 1-6
      c(15, 0.3), // 1-7
      c(15, 0.6, cap: false), // kod parchasi (rasm sifatida)
      c(16, 0.2), // 1-8 (matnda tilga olinmagan)
      c(17, 0.3), // 1-9
      c(17, 0.6), // 1-10
    ];
    final mentions = {
      '1-6': [13, 15],
      '1-7': [15],
      '1-9': [17],
      '1-10': [17],
      '8': [40], // shovqin
    };
    final out = FigureService.assign(cands, mentions);
    expect({for (final x in out) x.label: x.page}, {
      '1-6': 14,
      '1-7': 15,
      '1-8': 16,
      '1-9': 17,
      '1-10': 17,
    });
    expect(out.firstWhere((x) => x.label == '1-7').y0, 0.3);
  });

  test('mentionPages: turli yozilishlar', () {
    final m = FigureService.mentionPages([
      'As shown in Figure 1-4, users connect…',
      'see Fig. 2.3 and figure 1-4',
      'Как показано на рис. 3-1',
    ]);
    expect(m['1-4'], [1, 2]);
    expect(m['2-3'], [2]);
    expect(m['3-1'], [3]);
  });

  test('injectFigures: havoladan keyingi xatboshiga joylanadi', () {
    const md = 'Load balancer trafikni taqsimlaydi (1-4-rasm).\n\n'
        'Rasmda ko\'rinadiganidek:\n\n'
        '- birinchi band, 1-5-rasm\n'
        '- ikkinchi band\n\n'
        'Oxiri.\n\n'
        '```\ncode 1-6-rasm\n```';
    final r = injectFigures(md, [f('1-4'), f('1-5'), f('1-6'), f('9-9')]);
    final s = r.markdown;
    expect(s.indexOf('learner-fig:1-4'), greaterThan(s.indexOf('(1-4-rasm).')));
    expect(s.indexOf('learner-fig:1-4'), lessThan(s.indexOf('Rasmda')));
    // Ro'yxat ichidagi havola — butun ro'yxatdan keyin.
    expect(s.indexOf('learner-fig:1-5'), greaterThan(s.indexOf('ikkinchi band')));
    expect(s.indexOf('learner-fig:1-5'), lessThan(s.indexOf('Oxiri')));
    // Kod bloki ichidagi havola hisobga olinmaydi.
    expect(s.contains('learner-fig:1-6'), isFalse);
    expect(r.rest.map((x) => x.label), ['1-6', '9-9']);
    // Inglizcha va ruscha havolalar ham.
    expect(injectFigures('See Figure 1-4.', [f('1-4')]).rest, isEmpty);
    expect(injectFigures('См. рис. 1-4.', [f('1-4')]).rest, isEmpty);
  });

  final pdf = Platform.environment['FIG_PDF'];
  test('haqiqiy PDF: rasmlar topiladi', () async {
    FigureService.initEngine = pdfrxInitialize;
    await pdfrxInitialize();
    final cands = await FigureService.findCandidates(pdf!);
    final doc = await PdfDocument.openFile(pdf);
    final texts = [for (final p in doc.pages) (await p.loadText())?.fullText ?? ''];
    await doc.dispose();
    final figs = FigureService.assign(cands, FigureService.mentionPages(texts));
    // ignore: avoid_print
    print('${cands.length} nomzod, ${figs.length} rasm: ${figs.map((f) => '${f.label}@${f.page}').join(' ')}');
    expect(figs, isNotEmpty);
  }, skip: pdf == null, timeout: const Timeout(Duration(minutes: 5)));
}
