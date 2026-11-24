import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

/// Veb-sahifadan olingan matn.
class WebPage {
  WebPage(this.url, this.title, this.text);
  final String url;
  final String title;

  /// Markdown ko'rinishidagi asosiy matn (sarlavhalar, ro'yxatlar, kod bloklari, jadvallar).
  final String text;
}

/// Havola tekshiruvi: sahifaning o'zi va menyusidan topilgan shu bo'limdagi sahifalar.
class WebProbe {
  WebProbe(this.page, this.sectionUrls);
  final WebPage page;
  final List<String> sectionUrls;
  bool get hasSection => sectionUrls.length >= 3;
}

class WebSourceException implements Exception {
  WebSourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Veb-sahifalarni yuklab, o'qiladigan matnga aylantiradi.
class WebSource {
  WebSource({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  /// Bitta bo'limdan olinadigan eng ko'p sahifalar.
  static const maxPages = 250;

  static const _headers = {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Learner/1.0',
    'accept': 'text/html,application/xhtml+xml',
    'accept-language': 'en,ru;q=0.8,uz;q=0.6',
  };

  static Uri? parseUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty || !u.host.contains('.')) return null;
    return u;
  }

  Future<({Uri url, String body})> _get(Uri url) async {
    final http.Response r;
    try {
      r = await _http.get(url, headers: _headers).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw WebSourceException('timeout: $url');
    } catch (e) {
      throw WebSourceException('$e');
    }
    if (r.statusCode >= 400) throw WebSourceException('HTTP ${r.statusCode}: $url');
    final ct = r.headers['content-type'] ?? '';
    if (ct.isNotEmpty && !ct.contains('html') && !ct.contains('xml') && !ct.contains('text')) {
      throw WebSourceException('not a web page ($ct)');
    }
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    return (url: r.request?.url ?? url, body: body);
  }

  /// Sahifani ochadi va shu bo'limning boshqa sahifalarini (menyu tartibida) topadi.
  Future<WebProbe> probe(Uri url) async {
    final res = await _get(url);
    final doc = html.parse(res.body);
    final links = sectionLinks(doc, res.url);
    final page = extract(doc, res.url);
    return WebProbe(page, links);
  }

  /// Sahifalarni yuklaydi (bir vaqtda 4 tadan). Matni bir xil sahifalar (masalan, `/php/` va
  /// `/php/default.asp`) bir marta olinadi. Ochilmagan sahifalar o'tkazib yuboriladi.
  Future<List<WebPage>> fetchAll(List<String> urls, {void Function(int done, int total)? onProgress}) async {
    final results = List<WebPage?>.filled(urls.length, null);
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < urls.length) {
        final i = next++;
        try {
          final r = await _get(Uri.parse(urls[i]));
          results[i] = extract(html.parse(r.body), r.url);
        } catch (_) {}
        done++;
        onProgress?.call(done, urls.length);
      }
    }

    await Future.wait([for (var w = 0; w < 4; w++) worker()]);
    final seen = <String>{};
    final out = <WebPage>[];
    for (final p in results) {
      if (p == null || p.text.trim().length < 80) continue;
      final key = p.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!seen.add(key)) continue;
      out.add(p);
    }
    return out;
  }

  // ---------------------------------------------------------------- Bo'lim havolalari

  static final _pageExt = RegExp(r'(\.(s?html?|php|aspx?|jsp|md))?$', caseSensitive: false);

  /// Bo'lim prefiksi: URL yo'lining katalogi (`/php/php_intro.asp` → `/php/`).
  static String sectionPrefix(Uri u) {
    final path = u.path.isEmpty ? '/' : u.path;
    if (path.endsWith('/')) return path;
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i + 1);
  }

  static String _norm(Uri u) =>
      Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null, path: u.path).toString();

  /// Darslik bo'lmagan sahifalar: funksiyalar ma'lumotnomasi, quiz, sertifikat, mashq va muharrir sahifalari.
  static final _notTutorial = RegExp(
      r'(^|[_-])(func|ref|reference|keywords?|quiz|exercises?|challenges?|certificate|certified|compiler|editor|tryit|syllabus|study[_-]?plan|bootcamp|exams?|examples?|interview[_-]?(questions|prep)|server|howto)([_.-]|$)',
      caseSensitive: false);

  /// Shu sahifadagi menyudan bo'limning sahifalarini topadi (hujjat tartibida).
  static List<String> sectionLinks(dom.Document doc, Uri base) {
    final prefix = sectionPrefix(base);
    if (prefix == '/') return const [];
    bool ok(Uri u) {
      if (u.host != base.host) return false;
      if (!u.path.startsWith(prefix)) return false;
      final last = u.pathSegments.isEmpty ? '' : u.pathSegments.last;
      if (_notTutorial.hasMatch(last)) return false;
      if (last.contains('.') && !_pageExt.hasMatch(last)) return false;
      return _pageExt.firstMatch(last)?.group(1) != null || !last.contains('.');
    }

    // Har havola qaysi konteynerda turganini hisoblab, eng ko'p bo'lim havolasi bor menyuni tanlaymiz.
    final anchors = doc.querySelectorAll('a[href]');
    final valid = <dom.Element, String>{};
    for (final a in anchors) {
      final href = a.attributes['href']!.trim();
      if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:') || href.startsWith('mailto:')) continue;
      Uri u;
      try {
        u = base.resolve(href);
      } catch (_) {
        continue;
      }
      if (!ok(u)) continue;
      valid[a] = _norm(u);
    }
    if (valid.isEmpty) return const [];
    final counts = <dom.Element, int>{};
    for (final a in valid.keys) {
      var e = a.parent;
      var depth = 0;
      while (e != null && depth < 8) {
        counts[e] = (counts[e] ?? 0) + 1;
        e = e.parent;
        depth++;
      }
    }
    final distinctTotal = valid.values.toSet().length;
    // Bo'lim havolalarining kamida 60% ini o'z ichiga olgan eng kichik konteyner — menyu.
    dom.Element? menu;
    for (final e in counts.keys) {
      final inside = valid.entries.where((v) => _isInside(v.key, e)).map((v) => v.value).toSet().length;
      if (inside >= distinctTotal * 0.6 && inside >= 3) {
        if (menu == null || _depth(e) > _depth(menu)) menu = e;
      }
    }
    final ordered = <String>[];
    final seen = <String>{};
    void add(String u) {
      if (seen.add(u)) ordered.add(u);
    }

    add(_norm(base));
    for (final v in valid.entries) {
      if (menu == null || _isInside(v.key, menu)) add(v.value);
    }
    return ordered.length > maxPages ? ordered.sublist(0, maxPages) : ordered;
  }

  static bool _isInside(dom.Element a, dom.Element container) {
    dom.Node? e = a;
    while (e != null) {
      if (identical(e, container)) return true;
      e = e.parent;
    }
    return false;
  }

  static int _depth(dom.Element e) {
    var d = 0;
    dom.Node? x = e;
    while (x != null) {
      d++;
      x = x.parent;
    }
    return d;
  }

  // ---------------------------------------------------------------- Matnni ajratish

  static final _junk = RegExp(
      r'(^|[-_ ])(ads?|advert\w*|adsbygoogle|adcontainer|banner|leaderboard|skyscraper|cookies?|consent|share|social|newsletter|promo|sponsor\w*|nextprev|breadcrumbs?|comments?|related|footer|sidebar|toc|btn)([-_ ]|$)',
      caseSensitive: false);

  /// So'z ichida ham uchrasa reklama deb hisoblanadiganlar (masalan, `mainLeaderboard`).
  static final _junkAnywhere =
      RegExp(r'leaderboard|skyscraper|adsbygoogle|adcontainer|advert|sponsored|cookie-?banner', caseSensitive: false);

  static const _dropTags = {
    'script', 'style', 'noscript', 'svg', 'iframe', 'form', 'nav', 'header', 'footer', 'aside',
    'button', 'select', 'input', 'textarea', 'canvas', 'video', 'audio', 'template', 'link', 'meta',
  };

  /// Sahifaning asosiy matnini Markdown ko'rinishida oladi.
  static WebPage extract(dom.Document doc, Uri url) {
    final titleTag = doc.querySelector('title')?.text.trim() ?? '';
    final root = _mainElement(doc);
    // Keraksiz elementlarni olib tashlash
    for (final e in root.querySelectorAll('*').toList()) {
      if (_dropTags.contains(e.localName)) {
        e.remove();
        continue;
      }
      final id = e.id;
      final cls = e.className;
      if ((id.isNotEmpty && (_junk.hasMatch(id) || _junkAnywhere.hasMatch(id))) ||
          (cls.isNotEmpty && (_junk.hasMatch(cls) || _junkAnywhere.hasMatch(cls)))) {
        e.remove();
      }
    }
    final h1 = root.querySelector('h1')?.text.trim();
    final title = (h1 != null && h1.isNotEmpty) ? _squash(h1) : titleTag;
    final md = _MdWriter()..block(root);
    return WebPage(url.toString(), title, md.result());
  }

  static dom.Element _mainElement(dom.Document doc) {
    final body = doc.body ?? doc.documentElement!;
    for (final sel in [
      '#main', 'main', '[role=main]', 'article', '#content', '#mw-content-text', '.post-content',
      '.entry-content', '.article-content', '.markdown-body', '.content', '#primary',
    ]) {
      final e = doc.querySelector(sel);
      if (e != null && e.text.trim().length > 120) return e;
    }
    // Matn eng zich joylashgan konteyner: matnning ≥85% ini qamragan eng ichki div/section.
    final scored = <(dom.Element, int)>[];
    var max = 0;
    for (final e in body.querySelectorAll('div, section')) {
      var score = 0;
      for (final p in e.querySelectorAll('p, pre, li, h2, h3')) {
        score += p.text.trim().length;
      }
      scored.add((e, score));
      if (score > max) max = score;
    }
    if (max < 200) return body;
    dom.Element best = body;
    var bestDepth = -1;
    for (final (e, score) in scored) {
      if (score < max * 0.85) continue;
      final d = _depth(e);
      if (d > bestDepth) {
        best = e;
        bestDepth = d;
      }
    }
    return best;
  }

  static String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// HTML → Markdown (soddalashtirilgan).
class _MdWriter {
  final _out = StringBuffer();

  String result() => _out
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  void _para(String s) {
    final t = s.trim();
    if (t.isEmpty) return;
    _out.write('\n\n$t\n\n');
  }

  static bool _isCodeBox(dom.Element e) {
    final c = e.className.toLowerCase();
    return c.contains('w3-code') || c.contains('code-block') || c.contains('highlight') && e.localName == 'div' ||
        c.contains('codehilite') || c.contains('sourcecode');
  }

  void block(dom.Element e) {
    for (final n in e.nodes) {
      if (n is dom.Text) {
        final t = n.text.replaceAll(RegExp(r'\s+'), ' ');
        if (t.trim().isNotEmpty) _out.write(t);
        continue;
      }
      if (n is! dom.Element) continue;
      final tag = n.localName;
      if (tag == 'pre' || _isCodeBox(n)) {
        final code = _codeText(n).trimRight();
        if (code.trim().isNotEmpty) _out.write('\n\n```\n${_dedent(code)}\n```\n\n');
        continue;
      }
      switch (tag) {
        case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
          final level = int.parse(tag!.substring(1));
          final t = _inline(n);
          if (t.isNotEmpty) _out.write('\n\n${'#' * level} $t\n\n');
        case 'p':
          _para(_inline(n));
        case 'br':
          _out.write('\n');
        case 'hr':
          _out.write('\n\n---\n\n');
        case 'ul' || 'ol':
          _list(n, 0);
        case 'table':
          _table(n);
        case 'blockquote':
          final t = _inline(n);
          if (t.isNotEmpty) _out.write('\n\n> $t\n\n');
        case 'img':
          final alt = n.attributes['alt']?.trim() ?? '';
          if (alt.length > 3) _out.write('\n\n[Image: $alt]\n\n');
        case 'dl':
          for (final c in n.children) {
            final t = _inline(c);
            if (t.isEmpty) continue;
            _out.write(c.localName == 'dt' ? '\n\n**$t**\n' : '$t\n');
          }
        case 'a' || 'span' || 'strong' || 'b' || 'em' || 'i' || 'code' || 'kbd' || 'sup' || 'sub' || 'mark' || 'small' || 'u':
          _out.write(_inlineNode(n));
        default:
          _out.write('\n');
          block(n);
          _out.write('\n');
      }
    }
  }

  void _list(dom.Element list, int depth) {
    var i = 1;
    _out.write('\n');
    for (final li in list.children.where((c) => c.localName == 'li')) {
      final nested = li.children.where((c) => c.localName == 'ul' || c.localName == 'ol').toList();
      for (final x in nested) {
        x.remove();
      }
      final t = _inline(li);
      final bullet = list.localName == 'ol' ? '${i++}.' : '-';
      if (t.isNotEmpty) _out.write('${'  ' * depth}$bullet $t\n');
      for (final x in nested) {
        _list(x, depth + 1);
      }
    }
    _out.write('\n');
  }

  void _table(dom.Element t) {
    final rows = t.querySelectorAll('tr');
    if (rows.isEmpty) return;
    final cells = [
      for (final r in rows)
        [for (final c in r.children.where((c) => c.localName == 'td' || c.localName == 'th')) _inline(c).replaceAll('|', '\\|')],
    ].where((r) => r.isNotEmpty).toList();
    if (cells.isEmpty) return;
    final width = cells.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    _out.write('\n\n');
    for (var i = 0; i < cells.length; i++) {
      final r = [...cells[i], for (var k = cells[i].length; k < width; k++) ''];
      _out.write('| ${r.join(' | ')} |\n');
      if (i == 0) _out.write('|${List.filled(width, ' --- ').join('|')}|\n');
    }
    _out.write('\n');
  }

  static String _inline(dom.Element e) =>
      e.nodes.map(_inlineNode).join().replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r' *\n *'), ' ').trim();

  static String _inlineNode(dom.Node n) {
    if (n is dom.Text) return n.text.replaceAll(RegExp(r'\s+'), ' ');
    if (n is! dom.Element) return '';
    final inner = n.nodes.map(_inlineNode).join();
    switch (n.localName) {
      case 'code' || 'kbd':
        final t = n.text.trim();
        return t.isEmpty ? '' : '`${t.replaceAll('`', "'")}`';
      case 'strong' || 'b':
        return inner.trim().isEmpty ? inner : '**${inner.trim()}** ';
      case 'em' || 'i':
        return inner.trim().isEmpty ? inner : '*${inner.trim()}* ';
      case 'br':
        return '\n';
      case 'img':
        return '';
      default:
        return inner;
    }
  }

  /// Kod blokidagi matn: `<br>` → yangi qator, bo'shliqlar saqlanadi.
  static String _codeText(dom.Node n) {
    if (n is dom.Text) return n.text;
    if (n is! dom.Element) return '';
    if (n.localName == 'br') return '\n';
    final inner = n.nodes.map(_codeText).join();
    final blockish = n.localName == 'div' || n.localName == 'p' || n.localName == 'li' || n.localName == 'tr';
    return blockish && !inner.endsWith('\n') ? '$inner\n' : inner;
  }

  static String _dedent(String code) {
    final lines = code.replaceAll('\r\n', '\n').replaceAll(' ', ' ').split('\n');
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    var min = 1 << 30;
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      final ind = l.length - l.trimLeft().length;
      if (ind < min) min = ind;
    }
    if (min == 1 << 30 || min == 0) return lines.join('\n');
    return lines.map((l) => l.length >= min ? l.substring(min) : l.trimLeft()).join('\n');
  }
}
