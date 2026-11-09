import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../db/repository.dart';
import '../models/models.dart';

/// Rasm nomzodi: sahifadagi matn bo'lmagan "siyoh" bloki (PDF nuqtalarida, yuqori-chapdan).
class FigureCandidate {
  FigureCandidate(this.page, this.left, this.top, this.right, this.bottom, {this.captioned = false});
  final int page;
  final double left, top, right, bottom;

  /// Ostida/ustida "Figure …" yozuvi bor (matn yoki rasm ichidagi alohida qisqa qator).
  final bool captioned;
  double get width => right - left;
  double get height => bottom - top;
  @override
  String toString() =>
      'p$page [${left.toStringAsFixed(2)},${top.toStringAsFixed(2)} – ${right.toStringAsFixed(2)},${bottom.toStringAsFixed(2)}]${captioned ? ' cap' : ''}';
}

/// Kitobdagi rasmlarni topish, ularni matndagi "Figure 1-4" havolalariga bog'lash va chizish.
///
/// Ko'p kitoblarda rasm (va uning "Figure 1-4" yozuvi) PDF ichida tayyor surat sifatida turadi,
/// matn qatlamida esa faqat havolalar bor. Shuning uchun sahifa past aniqlikda chiziladi,
/// matn harflari joyi niqoblanadi, qolgan "siyoh" bloklari rasm nomzodi bo'ladi. So'ng nomzodlar
/// tartib bo'yicha havolalar bilan juftlanadi (rasm odatda havola turgan sahifa atrofida bo'ladi).
class FigureService {
  FigureService(this.repo);
  final Repository repo;

  /// Testlarda `pdfrxInitialize` bilan almashtiriladi.
  static Future<void> Function() initEngine = pdfrxFlutterInitialize;
  static void Function(int page)? debugProgress;

  final _bookFigs = <int, Future<List<BookFigure>>>{};
  final _running = <int, Future<void>>{};

  // ---------------- Aniqlash ----------------

  /// Kitob rasmlarini aniqlab, bazaga yozadi.
  Future<void> detectBook(int bookId) {
    return _running[bookId] ??= () async {
      try {
        final book = await repo.book(bookId);
        if (book == null) return;
        // Havolalar pdfium matnidan olinadi: syncfusion matnida ba'zan ortiqcha harflar bo'ladi ("yFigure 1-4").
        final texts = <String>[];
        final cands = await findCandidates(book.filePath, pageTexts: texts);
        if (texts.every((t) => t.isEmpty)) texts.addAll(await repo.pages(bookId));
        final mentions = mentionPages(texts);
        final figs = assign(cands, mentions);
        debugPrint('figures: book $bookId — ${cands.length} candidates, ${mentions.length} labels, ${figs.length} figures');
        await repo.replaceFigures(bookId, figs);
        _bookFigs.remove(bookId);
      } finally {
        _running.remove(bookId);
      }
    }();
  }

  Future<List<BookFigure>> bookFigures(int bookId) =>
      _bookFigs[bookId] ??= repo.figures(bookId);

  /// Qismga tegishli rasmlar: qism matnida tilga olinganlar + qism sahifalaridagilar.
  Future<List<BookFigure>> sectionFigures(Section section, String sourceText) async {
    final all = await bookFigures(section.bookId);
    if (all.isEmpty) return const [];
    final mentioned = {for (final m in _mentionRe.allMatches(sourceText)) _label(m)};
    final out = all
        .where((f) =>
            mentioned.contains(f.label) ||
            (f.page >= section.startPage && f.page <= section.endPage))
        .toList()
      ..sort((a, b) => a.page != b.page ? a.page.compareTo(b.page) : a.y0.compareTo(b.y0));
    return out;
  }

  /// Kitob matnidagi havolalar: "Figure 1-4", "Fig. 2.3", "Рис. 1-4", "Рисунок 5".
  static final _mentionRe = RegExp(
    r'(?<![\p{L}\p{N}])(?:figure|fig\.|рис\.|рисунок|рисунке|abbildung|abb\.)\s*(\d{1,3})(?:\s*[-–‑.]\s*(\d{1,3}))?',
    caseSensitive: false,
    unicode: true,
  );

  static String _label(RegExpMatch m) => m.group(2) == null ? m.group(1)! : '${m.group(1)}-${m.group(2)}';

  /// Har bir rasm raqami tilga olingan sahifalar (1-based).
  static Map<String, List<int>> mentionPages(List<String> pages) {
    final out = <String, List<int>>{};
    for (var i = 0; i < pages.length; i++) {
      for (final m in _mentionRe.allMatches(pages[i])) {
        final l = out.putIfAbsent(_label(m), () => []);
        if (l.isEmpty || l.last != i + 1) l.add(i + 1);
      }
    }
    return out;
  }

  static List<int> _labelKey(String l) => l.split('-').map(int.parse).toList();

  static int _cmpLabel(String a, String b) {
    final x = _labelKey(a), y = _labelKey(b);
    for (var i = 0; i < math.min(x.length, y.length); i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return x.length.compareTo(y.length);
  }

  /// Nomzodlarni havolalar bilan juftlash (dinamik dasturlash).
  ///
  /// Rasmlar kitobda raqam tartibida keladi, shuning uchun raqamlar ketma-ketligi va nomzodlar
  /// ketma-ketligi tartibni buzmasdan juftlanadi. Har bir juftlik ball oladi: rasm havola turgan
  /// sahifada yoki undan keyingi sahifada bo'lsa — yuqori, bitta oldin — o'rtacha. Matnda tilga
  /// olinmagan raqam (masalan, 1-8) faqat qo'shni raqamlar oralig'idagi nomzodni oladi, kichik ball bilan.
  /// Ortiqcha nomzodlar (kod rasmi, muqova, bezak) shunchaki tashlab ketiladi.
  static List<BookFigure> assign(List<FigureCandidate> cands, Map<String, List<int>> mentions) {
    if (cands.isEmpty || mentions.isEmpty) return const [];
    cands = [...cands]..sort((a, b) => a.page != b.page ? a.page.compareTo(b.page) : a.top.compareTo(b.top));

    // Kitob "1-4" uslubida raqamlasa, yakka "Figure 8" kabi havolalar shovqin.
    final twoPart = mentions.keys.where((l) => l.contains('-')).length;
    if (twoPart * 2 > mentions.length) {
      mentions = {
        for (final e in mentions.entries)
          if (e.key.contains('-')) e.key: e.value,
      };
    }
    // Bob ichidagi tushib qolgan raqamlarni to'ldirish (1-7, 1-9 bor → 1-8 ham bor).
    final labels = <String>{...mentions.keys};
    final maxByChapter = <int, int>{};
    for (final l in mentions.keys) {
      final k = _labelKey(l);
      if (k.length == 2) maxByChapter[k[0]] = math.max(maxByChapter[k[0]] ?? 0, k[1]);
    }
    maxByChapter.forEach((c, max) {
      if (max > 60) return;
      for (var n = 1; n <= max; n++) {
        labels.add('$c-$n');
      }
    });
    final ordered = labels.toList()..sort(_cmpLabel);
    final n = ordered.length, m = cands.length;

    // Tilga olinmagan raqamlar uchun sahifa oralig'i: oldingi va keyingi havolalar orasida.
    final lo = List<int>.filled(n, 0), hi = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (mentions[ordered[i]] != null) continue;
      int? prev, next;
      for (var t = i - 1; t >= 0 && prev == null; t--) {
        prev = mentions[ordered[t]]?.first;
      }
      for (var t = i + 1; t < n && next == null; t++) {
        next = mentions[ordered[t]]?.last;
      }
      if (prev == null) {
        // Bobning boshidagi tilga olinmagan rasm: keyingi havoladan oldin.
        int? nextFirst;
        for (var t = i + 1; t < n && nextFirst == null; t++) {
          nextFirst = mentions[ordered[t]]?.first;
        }
        lo[i] = (nextFirst ?? 0) - 4;
        hi[i] = nextFirst ?? 0;
      } else {
        lo[i] = prev - 1;
        hi[i] = next != null ? next + 2 : prev + 6;
      }
    }

    double score(int i, int j) {
      final c = cands[j];
      final ms = mentions[ordered[i]];
      // Yozuvsiz blok (masalan, rasm qilib qo'yilgan kod) faqat boshqa iloj bo'lmasa olinadi.
      final pen = c.captioned ? 0.0 : 2.5;
      if (ms == null) return (c.page >= lo[i] && c.page <= hi[i]) ? 1.3 - pen : double.negativeInfinity;
      var best = double.negativeInfinity;
      for (var t = 0; t < ms.length; t++) {
        final d = c.page - ms[t];
        var v = switch (d) { 0 => 4.0, 1 => 3.5, -1 => 2.5, 2 => 2.0, _ => double.negativeInfinity };
        // Rasm odatda birinchi havola yonida turadi; keyingi havolalar ("In Figure 1-14, …") kuchsizroq.
        if (t > 0) v -= 0.75;
        if (v > best) best = v;
      }
      return best - pen;
    }

    // dp[i][j]: birinchi i ta raqam va j ta nomzod bilan eng yaxshi ball.
    final dp = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
    final how = List.generate(n + 1, (_) => Uint8List(m + 1)); // 0 raqam o'tkazildi, 1 nomzod, 2 juftlik
    for (var i = 1; i <= n; i++) {
      how[i][0] = 0;
    }
    for (var j = 1; j <= m; j++) {
      how[0][j] = 1;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        var best = dp[i - 1][j];
        var h = 0;
        if (dp[i][j - 1] > best) {
          best = dp[i][j - 1];
          h = 1;
        }
        final sc = score(i - 1, j - 1);
        if (sc.isFinite && sc > 0 && dp[i - 1][j - 1] + sc > best) {
          best = dp[i - 1][j - 1] + sc;
          h = 2;
        }
        dp[i][j] = best;
        how[i][j] = h;
      }
    }

    final out = <BookFigure>[];
    var i = n, j = m;
    while (i > 0 && j > 0) {
      switch (how[i][j]) {
        case 2:
          final c = cands[j - 1];
          out.add(BookFigure(
            label: ordered[i - 1],
            page: c.page,
            x0: c.left,
            y0: c.top,
            x1: c.right,
            y1: c.bottom,
          ));
          i--;
          j--;
        case 1:
          j--;
        default:
          i--;
      }
    }
    return out.reversed.toList();
  }

  /// Barcha sahifalardan rasm nomzodlarini topadi. Koordinatalar sahifaga nisbatan 0..1.
  /// [pageTexts] berilsa, har sahifa matni ham unga yoziladi.
  static Future<List<FigureCandidate>> findCandidates(String pdfPath, {List<String>? pageTexts}) async {
    await initEngine();
    final doc = await PdfDocument.openFile(pdfPath);
    final out = <FigureCandidate>[];
    var errors = 0;
    try {
      for (final page in doc.pages) {
        if (pageTexts != null) {
          var t = '';
          try {
            t = (await page.loadText())?.fullText ?? '';
          } catch (_) {}
          pageTexts.add(t);
        }
        try {
          for (final c in await _pageCandidates(page)) {
            out.add(FigureCandidate(
              page.pageNumber,
              c.left / page.width,
              c.top / page.height,
              c.right / page.width,
              c.bottom / page.height,
              captioned: c.captioned,
            ));
          }
        } catch (e) {
          errors++;
          if (errors <= 3) debugPrint('figures: page ${page.pageNumber}: $e');
        }
        if (debugProgress != null) debugProgress!(page.pageNumber);
        // UI qotmasligi uchun.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      await doc.dispose();
    }
    return out;
  }

  static const _scale = 0.6;

  static final _captionRe = RegExp(
    r'(?:^|\n)\s*(?:figure|fig\.|рис\.|рисунок|abbildung|abb\.|table|таблица)\s*\d',
    caseSensitive: false,
  );

  static Future<List<FigureCandidate>> _pageCandidates(PdfPage page) async {
    final w = (page.width * _scale).round();
    final h = (page.height * _scale).round();
    if (w < 20 || h < 20) return const [];
    final img = await page.render(fullWidth: w.toDouble(), fullHeight: h.toDouble());
    if (img == null) return const [];
    final px = Uint8List.fromList(img.pixels);
    img.dispose();
    final raw = await page.loadText();
    final rects = <List<int>>[];
    for (final r in raw?.charRects ?? const <PdfRect>[]) {
      if (r.isEmpty) continue;
      rects.add([
        (r.left * _scale).floor() - 2,
        ((page.height - r.top) * _scale).floor() - 2,
        (r.right * _scale).ceil() + 2,
        ((page.height - r.bottom) * _scale).ceil() + 2,
      ]);
    }
    // Matn ko'rinishidagi rasm yozuvlari ("Figure 1-4: …") qatorlari.
    final captionRows = <int>[];
    final text = raw?.fullText ?? '';
    for (final m in _captionRe.allMatches(text)) {
      final idx = m.start + m.group(0)!.indexOf(RegExp(r'\S'));
      if (idx < 0 || idx >= (raw?.charRects.length ?? 0)) continue;
      final r = raw!.charRects[idx];
      captionRows.add(((page.height - (r.top + r.bottom) / 2) * _scale).round());
    }
    return detectInPixels(px, w, h, rects, pageNumber: page.pageNumber, captionRows: captionRows)
        .map((c) => FigureCandidate(
              c.page,
              c.left / _scale,
              c.top / _scale,
              c.right / _scale,
              c.bottom / _scale,
              captioned: c.captioned,
            ))
        .toList();
  }

  /// BGRA piksellar + harf to'rtburchaklari (piksel) → rasm bloklari (piksel).
  static List<FigureCandidate> detectInPixels(
    Uint8List bgra,
    int w,
    int h,
    List<List<int>> charRects, {
    int pageNumber = 0,
    List<int> captionRows = const [],
  }) {
    final mask = Uint8List(w * h);
    // Har bir qatordagi harflar soni (bandlar orasidagi matnni aniqlash uchun).
    final textRows = List<int>.filled(h, 0);
    for (final r in charRects) {
      final x0 = r[0].clamp(0, w), x1 = r[2].clamp(0, w);
      final y0 = r[1].clamp(0, h), y1 = r[3].clamp(0, h);
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          mask[y * w + x] = 1;
        }
      }
      final cy = ((y0 + y1) ~/ 2).clamp(0, h - 1);
      textRows[cy]++;
    }

    bool ink(int i) {
      final o = i * 4;
      return bgra[o] < 225 || bgra[o + 1] < 225 || bgra[o + 2] < 225;
    }

    final rowInk = List<int>.filled(h, 0);
    for (var y = 0; y < h; y++) {
      var c = 0;
      final base = y * w;
      for (var x = 0; x < w; x++) {
        final i = base + x;
        if (mask[i] == 0 && ink(i)) c++;
      }
      rowInk[y] = c;
    }

    // 1) Xom bandlar (qatorlar orasidagi bo'shliq ≤ 6 px).
    final bands = <List<int>>[];
    int? start;
    var last = -100;
    for (var y = 0; y < h; y++) {
      if (rowInk[y] > 1) {
        if (start == null || y - last > 6) {
          if (start != null) bands.add([start, last]);
          start = y;
        }
        last = y;
      }
    }
    if (start != null) bands.add([start, last]);

    // 2) Yaqin bandlarni birlashtirish (rasm + uning ostidagi yozuv), orada oddiy matn bo'lmasa.
    final px = 1 / _scale; // 1 nuqta ≈ 0.6 px
    final merged = <List<int>>[];
    for (final b in bands) {
      if (merged.isNotEmpty) {
        final prev = merged.last;
        final gap = b[0] - prev[1];
        var chars = 0;
        for (var y = prev[1] + 1; y < b[0]; y++) {
          chars += textRows[y];
        }
        if (gap <= (30 / px) && chars <= 25) {
          prev[1] = b[1];
          prev[2] = b[0]; // oxirgi bo'lak boshi
          continue;
        }
      }
      merged.add([b[0], b[1], -1]);
    }

    // 3) Har bir band uchun gorizontal chegara, zichlik va bir rangli fon tekshiruvi.
    final out = <FigureCandidate>[];
    for (final b in merged) {
      final y0 = b[0], y1 = b[1];
      final bh = y1 - y0 + 1;
      if (bh < 40 * _scale) continue;
      var minX = w, maxX = -1, inkCount = 0;
      final hist = <int, int>{};
      for (var y = y0; y <= y1; y++) {
        final base = y * w;
        for (var x = 0; x < w; x++) {
          final i = base + x;
          if (mask[i] == 1 || !ink(i)) continue;
          inkCount++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          final o = i * 4;
          final q = (bgra[o] >> 4) << 8 | (bgra[o + 1] >> 4) << 4 | (bgra[o + 2] >> 4);
          hist[q] = (hist[q] ?? 0) + 1;
        }
      }
      if (maxX < 0) continue;
      final bw = maxX - minX + 1;
      if (bw < 80 * _scale) continue;
      final density = inkCount / (bw * bh);
      final dominant = hist.values.fold(0, math.max) / inkCount;
      // Kulrang fonli kod/izoh qutisi: bir xil rang, zich to'ldirilgan, ichida matn ko'p.
      var chars = 0;
      for (var y = y0; y <= y1; y++) {
        chars += textRows[y];
      }
      if (dominant > 0.6 && density > 0.4 && chars > 20) continue;
      // Asosan matndan iborat blok (rangli kod, harflar atrofidagi qoldiqlar).
      if (chars > 20 && inkCount < 0.04 * bw * bh) continue;
      // Rasm ichidagi vektor yozuvlarni ham qamrab olish.
      for (final r in charRects) {
        final cy = (r[1] + r[3]) ~/ 2;
        if (cy < y0 || cy > y1) continue;
        if (r[2] < minX - 20 || r[0] > maxX + 20) continue;
        minX = math.min(minX, r[0]);
        maxX = math.max(maxX, r[2]);
      }
      // Yozuv: rasm ichidagi oxirgi qisqa, tor, markazdagi qator yoki yaqin matnli "Figure …" qatori.
      var captioned = captionRows.any((r) => (r > y1 && r - y1 <= 30 * _scale) || (r < y0 && y0 - r <= 30 * _scale));
      // Pastki qator: oxiridan yuqoriga siyohli qatorlar, so'ng kamida 2 px bo'sh oraliq.
      var capTop = y1;
      while (capTop > y0 && rowInk[capTop - 1] > 0) {
        capTop--;
      }
      var gapRows = 0;
      while (capTop - gapRows - 1 > y0 && rowInk[capTop - gapRows - 1] == 0) {
        gapRows++;
      }
      if (!captioned && gapRows >= 2 && y1 - capTop + 1 <= 18 * _scale && capTop - gapRows > y0) {
        var cMin = w, cMax = -1;
        for (var y = capTop; y <= y1; y++) {
          final base = y * w;
          for (var x = 0; x < w; x++) {
            final i = base + x;
            if (mask[i] == 0 && ink(i)) {
              if (x < cMin) cMin = x;
              if (x > cMax) cMax = x;
            }
          }
        }
        final cw = cMax - cMin + 1;
        final mid = (cMin + cMax) / 2, bandMid = (minX + maxX) / 2;
        captioned = cMax >= 0 && cw <= 0.85 * bw && (mid - bandMid).abs() <= 0.15 * bw;
      }
      const pad = 4;
      out.add(FigureCandidate(
        pageNumber,
        math.max(0, minX - pad).toDouble(),
        math.max(0, y0 - pad).toDouble(),
        math.min(w, maxX + pad).toDouble(),
        math.min(h, y1 + pad).toDouble(),
        captioned: captioned,
      ));
    }
    return out;
  }

  // ---------------- Chizish ----------------

  final _docs = <String, Future<PdfDocument>>{};
  final _images = <String, Future<ui.Image?>>{};
  final _order = <String>[];

  Future<PdfDocument> _doc(String path) => _docs[path] ??= () async {
        await initEngine();
        return PdfDocument.openFile(path);
      }();

  /// Rasmni (yoki [fullPage] bo'lsa butun sahifani) yuqori aniqlikda chizadi. Natija keshlanadi.
  Future<ui.Image?> render(String pdfPath, BookFigure f, {bool fullPage = false, double scale = 3}) {
    final key = '$pdfPath|${f.page}|${fullPage ? 'page' : '${f.x0},${f.y0},${f.x1},${f.y1}'}|$scale';
    final hit = _images[key];
    if (hit != null) return hit;
    final fut = () async {
      final doc = await _doc(pdfPath);
      if (f.page < 1 || f.page > doc.pages.length) return null;
      final page = doc.pages[f.page - 1];
      final fw = page.width * scale, fh = page.height * scale;
      final img = fullPage
          ? await page.render(fullWidth: fw, fullHeight: fh)
          : await page.render(
              x: (f.x0 * fw).round(),
              y: (f.y0 * fh).round(),
              width: math.max(1, ((f.x1 - f.x0) * fw).round()),
              height: math.max(1, ((f.y1 - f.y0) * fh).round()),
              fullWidth: fw,
              fullHeight: fh,
            );
      if (img == null) return null;
      try {
        return await img.createImage();
      } finally {
        img.dispose();
      }
    }();
    _images[key] = fut;
    _order.add(key);
    while (_order.length > 48) {
      _images.remove(_order.removeAt(0));
    }
    fut.catchError((_) {
      _images.remove(key);
      return null;
    });
    return fut;
  }
}

/// Dars matnidagi rasm havolalarini topib, o'sha xatboshidan keyin rasmni joylash.
/// Qaytaradi: yangi Markdown va matnda havolasi topilmagan rasmlar.
({String markdown, List<BookFigure> rest}) injectFigures(String md, List<BookFigure> figs) {
  if (figs.isEmpty) return (markdown: md, rest: const []);
  final byLabel = {for (final f in figs) f.label: f};
  final re = RegExp(
    r'(?:(?<![\p{L}\p{N}])(?:figure|fig\.|rasm|расм|рис\.?|рисун\p{L}*)\s*(\d{1,3})(?:\s*[-–‑.]\s*(\d{1,3}))?)'
    r'|(?:(?<![\p{L}\p{N}])(\d{1,3})\s*[-–‑.]\s*(\d{1,3})\s*[-–‑]?\s*(?:rasm|расм|figure))',
    caseSensitive: false,
    unicode: true,
  );
  final inserts = <int, List<String>>{};
  final placed = <String>{};
  final listLine = RegExp(r'^\s*(?:[-*+]\s|\d+[.)]\s|\|)');

  // Kod bloklari ichiga joylamaslik.
  final fences = <List<int>>[];
  final fenceRe = RegExp(r'^```', multiLine: true);
  final fm = fenceRe.allMatches(md).toList();
  for (var i = 0; i + 1 < fm.length; i += 2) {
    fences.add([fm[i].start, fm[i + 1].end]);
  }
  bool inFence(int pos) => fences.any((f) => pos >= f[0] && pos <= f[1]);

  for (final m in re.allMatches(md)) {
    final label = m.group(1) != null
        ? (m.group(2) == null ? m.group(1)! : '${m.group(1)}-${m.group(2)}')
        : '${m.group(3)}-${m.group(4)}';
    if (!byLabel.containsKey(label) || placed.contains(label) || inFence(m.start)) continue;
    // Havola turgan blokning oxiri (ro'yxat yoki jadval bo'lsa — butun ro'yxatdan keyin).
    final lineStart = md.lastIndexOf('\n', m.start) + 1;
    final isList = listLine.hasMatch(md.substring(lineStart, math.min(md.length, lineStart + 12)));
    var pos = m.end;
    var at = md.length;
    while (true) {
      final idx = md.indexOf('\n\n', pos);
      if (idx < 0) break;
      if (inFence(idx)) {
        pos = idx + 2;
        continue;
      }
      final nextLineEnd = md.indexOf('\n', idx + 2);
      final next = md.substring(idx + 2, nextLineEnd < 0 ? md.length : nextLineEnd);
      if (isList && listLine.hasMatch(next)) {
        pos = idx + 2;
        continue;
      }
      at = idx;
      break;
    }
    inserts.putIfAbsent(at, () => []).add(label);
    placed.add(label);
  }

  final b = StringBuffer();
  var cur = 0;
  for (final at in inserts.keys.toList()..sort()) {
    b.write(md.substring(cur, at));
    for (final l in inserts[at]!) {
      b.write('\n\n![$l](learner-fig:$l)');
    }
    cur = at;
  }
  b.write(md.substring(cur));
  return (
    markdown: b.toString(),
    rest: figs.where((f) => !placed.contains(f.label)).toList(),
  );
}
