import 'dart:io';
import 'dart:isolate';

import 'package:pdfrx/pdfrx.dart' as pdfium;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfOutlineItem {
  PdfOutlineItem(this.title, this.page, this.level);
  final String title;
  final int page; // 1-based
  final int level;
}

class PdfExtraction {
  PdfExtraction(this.pages, this.outline, this.title, this.author);
  final List<String> pages;
  final List<PdfOutlineItem> outline;
  final String? title;
  final String? author;

  int get totalChars => pages.fold(0, (a, p) => a + p.length);
}

/// PDF dan sahifama-sahifa matn va mundarija (bookmark) ajratadi.
///
/// Matn pdfium orqali olinadi (o'z fon isolate'ida ishlaydi): syncfusion ba'zi kitoblarda
/// so'zlarga ortiqcha harf qo'shadi ("directlyy", "yFigure 1-4") va qatorlarni yopishtiradi.
/// pdfium ishlamagan yoki bo'sh qaytargan sahifalar uchun syncfusion zaxira sifatida qoladi.
/// Mundarija va metama'lumotlar syncfusion bilan alohida isolate'da olinadi.
class PdfService {
  /// Testlarda `pdfrxInitialize` bilan almashtiriladi.
  static Future<void> Function() initEngine = pdfium.pdfrxFlutterInitialize;

  static Future<PdfExtraction> extract(String path) async {
    final texts = await pdfiumPages(path);
    final fallback = texts == null
        ? null
        : <int>{for (var i = 0; i < texts.length; i++) if (texts[i].isEmpty) i};
    final ex = await Isolate.run(() => _extractSync(path, fallback));
    if (texts == null || texts.length != ex.pages.length) return ex;
    return PdfExtraction(
      [for (var i = 0; i < texts.length; i++) texts[i].isEmpty ? ex.pages[i] : texts[i]],
      ex.outline,
      ex.title,
      ex.author,
    );
  }

  /// Har sahifa matni pdfium bilan. Hujjat ochilmasa — null.
  static Future<List<String>?> pdfiumPages(String path) async {
    pdfium.PdfDocument doc;
    try {
      await initEngine();
      doc = await pdfium.PdfDocument.openFile(path);
    } catch (_) {
      return null;
    }
    try {
      final out = <String>[];
      for (final page in doc.pages) {
        var t = '';
        try {
          t = (await page.loadText())?.fullText ?? '';
        } catch (_) {}
        out.add(cleanPdfiumText(t));
      }
      return out;
    } finally {
      await doc.dispose();
    }
  }

  /// pdfium qator oxiridagi chiziqchani U+0002 bilan beradi (qator ham qo'shiladi).
  static String cleanPdfiumText(String s) => _clean(s.replaceAll('\u0002', '-').replaceAll('\u0000', ''));

  /// [textPages] — syncfusion bilan matni olinadigan sahifalar (0 dan); null bo'lsa hammasi.
  static PdfExtraction _extractSync(String path, Set<int>? textPages) {
    final bytes = File(path).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final count = doc.pages.count;
      final pages = <String>[];
      PdfTextExtractor? extractor;
      for (var i = 0; i < count; i++) {
        var text = '';
        if (textPages == null || textPages.contains(i)) {
          try {
            text = (extractor ??= PdfTextExtractor(doc)).extractText(startPageIndex: i, endPageIndex: i);
          } catch (_) {}
        }
        pages.add(_clean(text));
      }

      final outline = <PdfOutlineItem>[];
      try {
        void walk(PdfBookmarkBase base, int level) {
          for (var i = 0; i < base.count; i++) {
            final b = base[i];
            var page = -1;
            try {
              final dest = b.destination ?? b.namedDestination?.destination;
              if (dest != null) page = doc.pages.indexOf(dest.page) + 1;
            } catch (_) {}
            if (page > 0 && b.title.trim().isNotEmpty) {
              outline.add(PdfOutlineItem(b.title.trim(), page, level));
            }
            if (level < 2 && b.count > 0) walk(b, level + 1);
          }
        }

        walk(doc.bookmarks, 0);
      } catch (_) {}

      String? title;
      String? author;
      try {
        title = doc.documentInformation.title.trim();
        author = doc.documentInformation.author.trim();
      } catch (_) {}

      return PdfExtraction(
        pages,
        outline,
        (title == null || title.isEmpty) ? null : title,
        (author == null || author.isEmpty) ? null : author,
      );
    } finally {
      doc.dispose();
    }
  }

  static String _clean(String s) {
    return s
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t ]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
