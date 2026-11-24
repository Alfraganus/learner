import 'dart:convert';

import '../models/interview.dart';
import '../models/models.dart';
import 'repository.dart';

/// Intervyular uchun so'rovlar.
extension InterviewRepo on Repository {
  static const _select = '''
    SELECT i.*,
      (SELECT COUNT(*) FROM interview_items t WHERE t.interview_id = i.id) AS item_count,
      (SELECT COUNT(*) FROM interview_items t WHERE t.interview_id = i.id
         AND json_extract(t.analysis, '\$.verdict') = 'correct') AS n_correct,
      (SELECT COUNT(*) FROM interview_items t WHERE t.interview_id = i.id
         AND json_extract(t.analysis, '\$.verdict') = 'partial') AS n_partial,
      (SELECT COUNT(*) FROM interview_items t WHERE t.interview_id = i.id
         AND json_extract(t.analysis, '\$.verdict') IN ('incorrect', 'no_answer')) AS n_wrong,
      (SELECT COUNT(*) FROM interview_items t WHERE t.interview_id = i.id AND t.starred = 1) AS n_marked
    FROM interviews i''';

  Future<List<Interview>> interviews() async {
    final rows = await db.rawQuery('$_select ORDER BY i.created_at DESC');
    return rows.map(Interview.fromRow).toList();
  }

  Future<Interview?> interview(int id) async {
    final rows = await db.rawQuery('$_select WHERE i.id = ?', [id]);
    return rows.isEmpty ? null : Interview.fromRow(rows.first);
  }

  Future<int> insertInterview(String url, String lang) => db.insert('interviews', {
    'url': url,
    'lang': lang,
    'status': InterviewStatus.processing,
    'status_message': 'iv_step_info',
    'created_at': nowMs(),
  });

  Future<void> updateInterview(int id, Map<String, Object?> values) =>
      db.update('interviews', values, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteInterview(int id) => db.delete('interviews', where: 'id = ?', whereArgs: [id]);

  Future<List<int>> interviewsWithStatus(String status) async {
    final rows = await db.query('interviews', columns: ['id'], where: 'status = ?', whereArgs: [status]);
    return rows.map((r) => r['id'] as int).toList();
  }

  Future<String?> interviewTranscript(int id) async {
    final r = await db.query('interviews', columns: ['transcript'], where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first['transcript'] as String?;
  }

  Future<List<InterviewItem>> interviewItems(int interviewId) async {
    final rows = await db.query('interview_items', where: 'interview_id = ?', whereArgs: [interviewId], orderBy: 'idx');
    return rows.map(InterviewItem.fromRow).toList();
  }

  /// Savollar ro'yxatini almashtirish (tahlillar o'chadi). Foydalanuvchi belgilari (muhim, izoh,
  /// belgilangan parchalar) vaqti eng yaqin (20 soniyagacha) yangi savolga ko'chiriladi.
  Future<void> replaceInterviewItems(
    int interviewId,
    List<({double start, double end, Map<String, dynamic> question})> items,
  ) async {
    await db.transaction((txn) async {
      final marks = await txn.query(
        'interview_items',
        columns: ['start_sec', 'starred', 'note', 'highlights'],
        where:
            "interview_id = ? AND (starred = 1 OR IFNULL(note, '') != '' OR IFNULL(highlights, '') NOT IN ('', '[]'))",
        whereArgs: [interviewId],
      );
      await txn.delete('interview_items', where: 'interview_id = ?', whereArgs: [interviewId]);
      final b = txn.batch();
      for (var i = 0; i < items.length; i++) {
        b.insert('interview_items', {
          'interview_id': interviewId,
          'idx': i,
          'start_sec': items[i].start,
          'end_sec': items[i].end,
          'question': jsonEncode(items[i].question),
        });
      }
      await b.commit(noResult: true);
      if (marks.isEmpty || items.isEmpty) return;
      final fresh = await txn.query(
        'interview_items',
        columns: ['id', 'start_sec'],
        where: 'interview_id = ?',
        whereArgs: [interviewId],
      );
      for (final m in marks) {
        final t = (m['start_sec'] as num).toDouble();
        Map<String, Object?>? best;
        for (final f in fresh) {
          final d = ((f['start_sec'] as num).toDouble() - t).abs();
          if (d <= 20 && (best == null || d < ((best['start_sec'] as num).toDouble() - t).abs())) best = f;
        }
        if (best == null) continue;
        final cur = (await txn.query(
          'interview_items',
          columns: ['starred', 'note', 'highlights'],
          where: 'id = ?',
          whereArgs: [best['id']],
        )).first;
        final notes = [cur['note'], m['note']].whereType<String>().where((n) => n.trim().isNotEmpty);
        await txn.update(
          'interview_items',
          {
            'starred': (m['starred'] == 1 || cur['starred'] == 1) ? 1 : 0,
            'note': notes.isEmpty ? null : notes.join('\n\n'),
            'highlights': jsonEncode(
              {
                ...InterviewItem.decodeHighlights(cur['highlights'] as String?),
                ...InterviewItem.decodeHighlights(m['highlights'] as String?),
              }.toList(),
            ),
          },
          where: 'id = ?',
          whereArgs: [best['id']],
        );
      }
    });
  }

  /// Savolni muhim deb belgilash / izoh / belgilangan parchalarni saqlash.
  Future<void> updateItemMarks(int itemId, {bool? starred, String? note, List<String>? highlights}) => db.update(
    'interview_items',
    {
      'starred': ?(starred == null ? null : (starred ? 1 : 0)),
      'note': ?note,
      'highlights': ?(highlights == null ? null : jsonEncode(highlights)),
    },
    where: 'id = ?',
    whereArgs: [itemId],
  );

  Future<void> saveItemAnalysis(int itemId, Map<String, dynamic>? analysis) => db.update(
    'interview_items',
    {'analysis': analysis == null ? null : jsonEncode(analysis)},
    where: 'id = ?',
    whereArgs: [itemId],
  );
}
