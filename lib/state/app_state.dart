import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../db/repository.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/book_processor.dart';
import '../services/claude_service.dart';
import '../services/content_service.dart';
import '../services/figure_service.dart';
import '../services/rag_service.dart';
import '../services/secret_store.dart';

class AppState extends ChangeNotifier {
  AppState._(this.repo, this.claude) {
    rag = RagService(repo);
    figures = FigureService(repo);
    content = ContentService(repo, claude, rag);
    processor = BookProcessor(repo, claude, rag, _scheduleRefresh)
      ..langProvider = (() => lang)
      ..figures = figures
      ..onFiguresReady = _figuresReady;
  }

  final Repository repo;
  final ClaudeService claude;
  late final RagService rag;
  late final ContentService content;
  late final BookProcessor processor;
  late final FigureService figures;

  /// Rasmlar bazasi yangilanganda oshadi (ochiq darslar rasmlarni qayta yuklaydi).
  int figuresRev = 0;
  void _figuresReady() {
    figuresRev++;
    notifyListeners();
  }

  /// Rasmlari hali aniqlanmagan kitoblar uchun (eski importlar) fonda aniqlash.
  Future<void> detectMissingFigures() async {
    for (final id in await repo.booksWithoutFigures()) {
      try {
        await figures.detectBook(id);
        _figuresReady();
      } catch (_) {}
    }
  }

  /// Eski importlar matnini pdfium matniga yangilash (syncfusion "directlyy", "yFigure" kabi xatolar qo'shardi).
  Future<void> refreshOldText() async {
    for (final id in await repo.booksWithOldText()) {
      try {
        final r = await processor.refreshText(id);
        if (r != null) debugPrint('text: book $id — ${r.updated}/${r.total} chapters refreshed');
      } catch (e) {
        debugPrint('text: book $id — $e');
      }
    }
  }

  late final SecretStore _secrets = SecretStore(repo);

  /// O'rganish tili: darslar, quiz va javoblar shu tilda yaratiladi.
  String lang = 'uz';

  /// Interfeys tili: menyular, tugmalar, xabarlar.
  String uiLang = 'uz';
  ThemeMode themeMode = ThemeMode.system;
  String get model => claude.model;
  String get claudePath => claude.executableOverride;
  ClaudeMode get mode => claude.mode;
  bool get hasApiKey => claude.effectiveApiKey.isNotEmpty;
  S get s => S(uiLang);

  List<Category> categories = [];
  List<Book> allBooks = [];
  Book? lastBook;
  LearningStats? stats;

  /// [dataDir] — testlar uchun boshqa papka.
  static Future<AppState> create({String? dataDir, bool background = true}) async {
    final db = await AppDatabase.open(dir: dataDir);
    final repo = Repository(db);
    final claude = ClaudeService(workDir: p.join(db.dataDir.path, 'claude_work'));
    final st = AppState._(repo, claude);
    st.lang = await repo.getSetting('lang') ?? 'uz';
    st.uiLang = await repo.getSetting('ui_lang') ?? st.lang;
    S.ui = S(st.uiLang);
    st.themeMode = switch (await repo.getSetting('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    claude.model = await repo.getSetting('model') ?? 'sonnet';
    claude.executableOverride = await repo.getSetting('claude_path') ?? '';
    claude.mode = (await repo.getSetting('mode')) == 'api' ? ClaudeMode.api : ClaudeMode.cli;
    claude.apiKey = await st._secrets.read();
    await st.refresh();
    if (!background) return st;
    unawaited(() async {
      try {
        await st.rag.backfill();
      } catch (_) {}
      await st.processor.resumePending();
      await st.refreshOldText();
      await st.detectMissingFigures();
    }());
    return st;
  }

  Timer? _refreshTimer;
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 150), refresh);
  }

  Future<void> refresh() async {
    categories = await repo.categories();
    allBooks = await repo.books();
    lastBook = await repo.lastOpenedBook();
    stats = await repo.stats();
    notifyListeners();
  }

  List<Book> booksIn(int? categoryId) => categoryId == null
      ? allBooks
      : allBooks.where((b) => categoryId == -1 ? b.categoryId == null : b.categoryId == categoryId).toList();

  Future<void> setLang(String code) async {
    lang = code;
    await repo.setSetting('lang', code);
    notifyListeners();
  }

  Future<void> setUiLang(String code) async {
    uiLang = code;
    S.ui = S(code);
    await repo.setSetting('ui_lang', code);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await repo.setSetting('theme', m.name);
    notifyListeners();
  }

  Future<void> setModel(String m) async {
    claude.model = m;
    await repo.setSetting('model', m);
    notifyListeners();
  }

  Future<void> setMode(ClaudeMode m) async {
    claude.mode = m;
    await repo.setSetting('mode', m.name);
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    claude.apiKey = key.trim();
    await _secrets.write(key.trim());
    notifyListeners();
  }

  Future<void> setClaudePath(String path) async {
    claude.executableOverride = path;
    claude.resetResolution();
    await repo.setSetting('claude_path', path);
    notifyListeners();
  }

  // ---- Kategoriyalar ----
  Future<int?> addCategory(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final id = await repo.addCategory(name);
      await refresh();
      return id;
    } catch (_) {
      return null; // takroriy nom
    }
  }

  Future<void> renameCategory(int id, String name) async {
    if (name.trim().isEmpty) return;
    try {
      await repo.renameCategory(id, name);
    } catch (_) {}
    await refresh();
  }

  Future<void> deleteCategory(int id) async {
    await repo.deleteCategory(id);
    await refresh();
  }

  // ---- Kitoblar ----
  Future<void> importPdf(String path, int? categoryId) async {
    await processor.importPdf(path, categoryId);
    await refresh();
  }

  Future<void> retryBook(int id) async {
    unawaited(processor.process(id));
    await refresh();
  }

  Future<void> moveBook(int bookId, int? categoryId) async {
    await repo.updateBook(bookId, {'category_id': categoryId});
    await refresh();
  }

  Future<void> deleteBook(Book b) async {
    await repo.deleteBook(b.id);
    try {
      final f = File(b.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await refresh();
  }

  @override
  void dispose() {
    claude.killAll();
    super.dispose();
  }
}
