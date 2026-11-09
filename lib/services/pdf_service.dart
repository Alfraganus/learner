import 'dart:io';
import 'dart:isolate';

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
/// Og'ir ish alohida isolate'da bajariladi, UI qotmaydi.
class PdfService {
  static Future<PdfExtraction> extract(String path) =>
      Isolate.run(() => _extractSync(path));

  static PdfExtraction _extractSync(String path) {
    final bytes = File(path).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(doc);
      final count = doc.pages.count;
      final pages = <String>[];
      for (var i = 0; i < count; i++) {
        String text;
        try {
          text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        } catch (_) {
          text = '';
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
