import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite bazasi: sxema, indekslar va migratsiyalar.
class AppDatabase {
  AppDatabase._(this.db, this.dataDir);

  final Database db;

  /// Ilova ma'lumotlari papkasi (PDF nusxalari, claude ish papkasi).
  final Directory dataDir;

  static const _version = 3;

  /// [dir] berilmasa, ilova ma'lumotlari papkasi ishlatiladi (testlar uchun berish mumkin).
  static Future<AppDatabase> open({String? dir}) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    // LEARNER_DATA_DIR — boshqa papkada ishlatish (portable rejim, demo).
    dir ??= Platform.environment['LEARNER_DATA_DIR'];
    final Directory dataDir;
    if (dir != null) {
      dataDir = Directory(dir);
    } else {
      final support = await getApplicationSupportDirectory();
      dataDir = Directory(p.join(support.path, 'learner'));
    }
    await dataDir.create(recursive: true);
    final path = p.join(dataDir.path, 'learner.db');

    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = NORMAL');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final stmt in [..._schemaV1, ..._schemaV2, ..._schemaV3]) {
            batch.execute(stmt);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldV, newV) async {
          if (oldV < 2) {
            final batch = db.batch();
            for (final stmt in _schemaV2) {
              batch.execute(stmt);
            }
            await batch.commit(noResult: true);
          }
          if (oldV < 3) {
            final batch = db.batch();
            for (final stmt in _schemaV3) {
              batch.execute(stmt);
            }
            await batch.commit(noResult: true);
          }
        },
      ),
    );
    return AppDatabase._(db, dataDir);
  }

  static const List<String> _schemaV1 = [
    // --- Sozlamalar ---
    '''CREATE TABLE settings(
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    ) WITHOUT ROWID''',

    // --- Kategoriyalar ---
    '''CREATE TABLE categories(
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT NOT NULL COLLATE NOCASE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''',
    'CREATE UNIQUE INDEX idx_categories_name ON categories(name)',
    'CREATE INDEX idx_categories_sort ON categories(sort_order, name)',

    // --- Kitoblar ---
    '''CREATE TABLE books(
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      category_id     INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      title           TEXT NOT NULL,
      author          TEXT,
      file_path       TEXT NOT NULL,
      file_name       TEXT NOT NULL,
      page_count      INTEGER NOT NULL DEFAULT 0,
      source_lang     TEXT,
      status          TEXT NOT NULL DEFAULT 'processing',
      status_message  TEXT,
      created_at      INTEGER NOT NULL,
      last_opened_at  INTEGER,
      last_chapter_id INTEGER,
      last_section_id INTEGER,
      last_view       TEXT,
      last_scroll     REAL
    )''',
    'CREATE INDEX idx_books_category ON books(category_id, last_opened_at DESC)',
    'CREATE INDEX idx_books_last_opened ON books(last_opened_at DESC)',
    'CREATE INDEX idx_books_status ON books(status)',

    // --- PDF sahifalari matni ---
    '''CREATE TABLE book_pages(
      book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      page_no INTEGER NOT NULL,
      text    TEXT NOT NULL,
      PRIMARY KEY(book_id, page_no)
    ) WITHOUT ROWID''',

    // --- Boblar ---
    '''CREATE TABLE chapters(
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id    INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      idx        INTEGER NOT NULL,
      title      TEXT NOT NULL,
      start_page INTEGER NOT NULL,
      end_page   INTEGER NOT NULL
    )''',
    'CREATE UNIQUE INDEX idx_chapters_book ON chapters(book_id, idx)',

    // Bob nomlarining tarjimalari
    '''CREATE TABLE chapter_titles(
      chapter_id INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      lang       TEXT NOT NULL,
      title      TEXT NOT NULL,
      PRIMARY KEY(chapter_id, lang)
    ) WITHOUT ROWID''',

    // --- Qismlar (bob ichidagi bo'laklar) ---
    '''CREATE TABLE sections(
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      chapter_id  INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      book_id     INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      idx         INTEGER NOT NULL,
      start_page  INTEGER NOT NULL,
      end_page    INTEGER NOT NULL,
      source_text TEXT NOT NULL,
      word_count  INTEGER NOT NULL
    )''',
    'CREATE UNIQUE INDEX idx_sections_chapter ON sections(chapter_id, idx)',
    'CREATE INDEX idx_sections_book ON sections(book_id)',

    // --- Soddalashtirilgan darslar (har bir til uchun alohida) ---
    '''CREATE TABLE lessons(
      section_id INTEGER NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
      lang       TEXT NOT NULL,
      title      TEXT NOT NULL,
      content    TEXT NOT NULL,
      key_points TEXT NOT NULL,
      terms      TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY(section_id, lang)
    ) WITHOUT ROWID''',

    // --- O'qilgan qismlar ---
    '''CREATE TABLE section_progress(
      section_id   INTEGER PRIMARY KEY REFERENCES sections(id) ON DELETE CASCADE,
      book_id      INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      chapter_id   INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      completed_at INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_progress_book ON section_progress(book_id)',
    'CREATE INDEX idx_progress_chapter ON section_progress(chapter_id)',

    // --- Bob yakuni: savol-javob, quiz, mashqlar (JSON) ---
    '''CREATE TABLE chapter_reviews(
      chapter_id INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      lang       TEXT NOT NULL,
      kind       TEXT NOT NULL,
      data       TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY(chapter_id, lang, kind)
    ) WITHOUT ROWID''',

    // Quiz natijalari
    '''CREATE TABLE quiz_attempts(
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      chapter_id INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      book_id    INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      lang       TEXT NOT NULL,
      score      INTEGER NOT NULL,
      total      INTEGER NOT NULL,
      answers    TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_quiz_chapter ON quiz_attempts(chapter_id, created_at DESC)',
    'CREATE INDEX idx_quiz_book ON quiz_attempts(book_id)',

    // Mashqlarga javoblar va baholash
    '''CREATE TABLE exercise_answers(
      chapter_id   INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      lang         TEXT NOT NULL,
      exercise_idx INTEGER NOT NULL,
      answer       TEXT NOT NULL,
      feedback     TEXT,
      score        INTEGER,
      updated_at   INTEGER NOT NULL,
      PRIMARY KEY(chapter_id, lang, exercise_idx)
    ) WITHOUT ROWID''',

    // --- "Savol berish" suhbati ---
    '''CREATE TABLE chat_messages(
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id    INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      chapter_id INTEGER REFERENCES chapters(id) ON DELETE SET NULL,
      section_id INTEGER REFERENCES sections(id) ON DELETE SET NULL,
      role       TEXT NOT NULL,
      content    TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )''',
    'CREATE INDEX idx_chat_book ON chat_messages(book_id, id)',
    'CREATE INDEX idx_chat_chapter ON chat_messages(chapter_id, id)',
  ];

  /// v2: RAG (FTS5 to'liq matnli qidiruv) va javob manbalari.
  static const List<String> _schemaV2 = [
    // Qidiruv bo'laklari: kitob matni (source) va soddalashtirilgan darslar (lesson).
    '''CREATE TABLE rag_chunks(
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id    INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      chapter_id INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      section_id INTEGER NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
      kind       TEXT NOT NULL,
      lang       TEXT NOT NULL DEFAULT '',
      seq        INTEGER NOT NULL,
      page_start INTEGER NOT NULL,
      page_end   INTEGER NOT NULL,
      text       TEXT NOT NULL
    )''',
    'CREATE INDEX idx_rag_book ON rag_chunks(book_id, kind)',
    'CREATE INDEX idx_rag_section ON rag_chunks(section_id, kind, lang)',
    'CREATE INDEX idx_rag_chapter ON rag_chunks(chapter_id)',
    // FTS5 indeksi (bm25 reyting), rag_chunks bilan triggerlar orqali sinxron.
    '''CREATE VIRTUAL TABLE rag_fts USING fts5(
      text,
      content='rag_chunks',
      content_rowid='id',
      tokenize='porter unicode61 remove_diacritics 2'
    )''',
    '''CREATE TRIGGER rag_ai AFTER INSERT ON rag_chunks BEGIN
      INSERT INTO rag_fts(rowid, text) VALUES (new.id, new.text);
    END''',
    '''CREATE TRIGGER rag_ad AFTER DELETE ON rag_chunks BEGIN
      INSERT INTO rag_fts(rag_fts, rowid, text) VALUES ('delete', old.id, old.text);
    END''',
    '''CREATE TRIGGER rag_au AFTER UPDATE ON rag_chunks BEGIN
      INSERT INTO rag_fts(rag_fts, rowid, text) VALUES ('delete', old.id, old.text);
      INSERT INTO rag_fts(rowid, text) VALUES (new.id, new.text);
    END''',
    // Javob qaysi manbalarga tayangani (JSON).
    'ALTER TABLE chat_messages ADD COLUMN sources TEXT',
  ];

  /// v3: kitobdagi rasmlar (figure) — sahifa va rasm joylashgan to'rtburchak (0..1, yuqori-chapdan).
  static const List<String> _schemaV3 = [
    '''CREATE TABLE figures(
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      label   TEXT NOT NULL,
      page    INTEGER NOT NULL,
      x0 REAL NOT NULL, y0 REAL NOT NULL, x1 REAL NOT NULL, y1 REAL NOT NULL
    )''',
    'CREATE UNIQUE INDEX idx_figures_label ON figures(book_id, label)',
    'CREATE INDEX idx_figures_page ON figures(book_id, page)',
    'ALTER TABLE books ADD COLUMN figures_done INTEGER NOT NULL DEFAULT 0',
  ];
}
