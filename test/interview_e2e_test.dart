// Intervyu tahlilini haqiqiy YouTube video va `claude -p` bilan boshidan oxirigacha tekshirish.
// Ishga tushirish: IV_URL=<youtube havola> IV_DATA=<papka> flutter test test/interview_e2e_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learner/db/app_database.dart';
import 'package:learner/db/interview_repo.dart';
import 'package:learner/db/repository.dart';
import 'package:learner/models/interview.dart';
import 'package:learner/services/claude_service.dart';
import 'package:learner/services/interview_service.dart';
import 'package:learner/services/video_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  final url = Platform.environment['IV_URL'];
  final dataDir = Platform.environment['IV_DATA'];

  test('interview end to end', () async {
    final db = await AppDatabase.open(dir: dataDir);
    final repo = Repository(db);
    final claude = ClaudeService(workDir: p.join(dataDir!, 'claude_work'))
      ..model = 'sonnet'
      // ignore: avoid_print
      ..log = (m) => print('[${DateTime.now().toIso8601String().substring(11, 19)}] $m');
    var last = '';
    late InterviewService svc;
    svc = InterviewService(repo, claude, VideoTools(), () async {
      final ivs = await repo.interviews();
      if (ivs.isEmpty) return;
      final s = '${ivs.first.statusMessage} ${ivs.first.progress?.toStringAsFixed(2) ?? ''}';
      if (s != last) {
        last = s;
        // ignore: avoid_print
        print('  status: $s');
      }
    })
      ..langProvider = () => 'uz';
    final id = await svc.add(InterviewService.normalizeUrl(url!)!);
    await Future.delayed(const Duration(milliseconds: 300));
    while (svc.isActive(id)) {
      await Future.delayed(const Duration(seconds: 1));
    }
    final iv = (await repo.interview(id))!;
    final items = await repo.interviewItems(id);
    // ignore: avoid_print
    print('status=${iv.status} msg=${iv.statusMessage} items=${items.length} '
        'correct=${iv.correct} partial=${iv.partial} wrong=${iv.wrong}');
    final out = [
      for (final i in items)
        {'start': i.start, 'end': i.end, 'question': i.question, 'analysis': i.analysis},
    ];
    await File(p.join(dataDir, 'result.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    expect(iv.status, InterviewStatus.ready);
    expect(items, isNotEmpty);
    expect(items.every((i) => i.analyzed), isTrue);
    await db.db.close();
  }, timeout: const Timeout(Duration(minutes: 60)), skip: url == null || dataDir == null);
}
