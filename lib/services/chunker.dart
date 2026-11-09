/// Bob matnini taxminan teng qismlarga bo'ladi.
/// Hech bir qator tashlab ketilmaydi: barcha matn qaysidir qismga tushadi.
class Chunk {
  Chunk(this.startPage, this.endPage, this.text, this.words);
  final int startPage;
  final int endPage;
  final String text;
  final int words;
}

int countWords(String s) =>
    s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

List<Chunk> chunkPages(
  List<({int page, String text})> pages, {
  int targetWords = 1300,
  int maxWords = 1900,
  int minTailWords = 350,
}) {
  final chunks = <Chunk>[];
  final buf = StringBuffer();
  var words = 0;
  int? start;
  var lastPage = pages.isEmpty ? 1 : pages.first.page;

  void flush() {
    final text = buf.toString().trim();
    if (text.isNotEmpty) {
      chunks.add(Chunk(start ?? lastPage, lastPage, text, words));
    }
    buf.clear();
    words = 0;
    start = null;
  }

  final sentenceEnd = RegExp(r'''[.!?:;"”»)\]]\s*$''');

  for (final p in pages) {
    final lines = p.text.split('\n');
    for (final line in lines) {
      lastPage = p.page;
      start ??= p.page;
      buf.writeln(line);
      final w = countWords(line);
      words += w;
      final trimmed = line.trim();
      final atBoundary = trimmed.isEmpty || sentenceEnd.hasMatch(trimmed);
      if ((words >= targetWords && atBoundary) || words >= maxWords) {
        flush();
      }
    }
    if (buf.isNotEmpty) buf.writeln();
  }
  flush();

  // Juda kichik oxirgi qismni oldingisiga qo'shamiz.
  if (chunks.length >= 2 && chunks.last.words < minTailWords) {
    final last = chunks.removeLast();
    final prev = chunks.removeLast();
    chunks.add(Chunk(prev.startPage, last.endPage, '${prev.text}\n\n${last.text}',
        prev.words + last.words));
  }
  return chunks;
}

final _nonWord = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Solishtirish uchun: faqat harf va raqamlar, kichik harfda, "y" siz
/// (syncfusion "y" ni ortiqcha qo'shardi: "syystem", "yFigure"; qatorlarni ham yopishtirardi).
String _norm(String s) => s.toLowerCase().replaceAll(_nonWord, '').replaceAll('y', '');

/// Yangi (toza) matnni eski qismlar chegarasida bo'ladi: qismlar soni va chegaralari o'zgarmaydi,
/// shuning uchun yozib bo'lingan darslar o'z qismiga mos qoladi va hech bir qator tushib qolmaydi.
/// Chegara qator o'rtasiga tushsa, o'sha qator keyingi qismga o'tadi (takrorlanishi mumkin, yo'qolmaydi).
/// Matnlar mazmunan farq qilsa (umumiy uzunlik [tolerance] dan ko'p) — null.
List<Chunk>? realignChunks(
  List<({int page, String text})> pages,
  List<String> oldSections, {
  double tolerance = 0.02,
}) {
  if (oldSections.isEmpty) return null;
  final lines = <({int page, String text, int cum})>[];
  var cum = 0;
  for (final p in pages) {
    for (final l in p.text.split('\n')) {
      cum += _norm(l).length;
      lines.add((page: p.page, text: l, cum: cum));
    }
    lines.add((page: p.page, text: '', cum: cum));
  }
  final oldLens = [for (final s in oldSections) _norm(s).length];
  final oldTotal = oldLens.fold<int>(0, (a, b) => a + b);
  if (oldTotal == 0 || (cum - oldTotal).abs() > oldTotal * tolerance) return null;

  final out = <Chunk>[];
  var from = 0;
  var target = 0;
  for (var i = 0; i < oldSections.length; i++) {
    var to = lines.length;
    if (i < oldSections.length - 1) {
      target += oldLens[i];
      to = from;
      while (to < lines.length && lines[to].cum <= target) {
        to++;
      }
    }
    final slice = lines.sublist(from, to).where((l) => l.text.trim().isNotEmpty).toList();
    if (slice.isEmpty) return null;
    final text = lines.sublist(from, to).map((l) => l.text).join('\n').trim();
    out.add(Chunk(slice.first.page, slice.last.page, text, countWords(text)));
    from = to;
  }
  return out;
}
