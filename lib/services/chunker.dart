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
