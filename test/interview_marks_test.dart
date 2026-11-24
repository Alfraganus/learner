// Intervyu savollarini "muhim" deb belgilash: bayroqcha, izoh, belgilaganlarim ro'yxati va qayta tahlilda saqlanishi.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learner/db/interview_repo.dart';
import 'package:learner/screens/interview_screen.dart';
import 'package:learner/state/app_state.dart';
import 'package:learner/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  Future<(AppState, int)> setup() async {
    final dir = await Directory.systemTemp.createTemp('learner_marks');
    final state = await AppState.create(dataDir: dir.path, background: false);
    final repo = state.repo;
    final id = await repo.insertInterview('https://www.youtube.com/watch?v=abcdefghijk', state.s.lang);
    await repo.updateInterview(id, {
      'status': 'ready',
      'video_id': 'abcdefghijk',
      'title': 'Mock interview',
      'summary': '{"summary":"Test","frames":0}',
    });
    await repo.replaceInterviewItems(id, [
      (start: 10.0, end: 60.0, question: {'question': 'What is a hash map?', 'kind': 'theory'}),
      (start: 70.0, end: 200.0, question: {'question': 'Reverse a linked list', 'kind': 'coding'}),
    ]);
    final items = await repo.interviewItems(id);
    await repo.saveItemAnalysis(items[0].id, {
      'candidate_answer': 'It stores key value pairs.',
      'verdict': 'partial',
      'verdict_reason': 'Missed hashing and collisions.',
      'better_answer': 'A hash map uses a hash function…',
      'key_points': ['O(1) average lookup'],
      'screen': [],
      'resources': [],
    });
    await state.refresh();
    return (state, id);
  }

  testWidgets('flag, note and marked list', (tester) async {
    final (state, id) = (await tester.runAsync(setup))!;
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: InterviewScreen(interviewId: id)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    final s = state.s;
    expect(find.text(s.t('iv_marked_title')), findsNothing);
    expect(find.byIcon(Icons.outlined_flag_rounded), findsNWidgets(2));

    // 1-savolni belgilaymiz.
    await tester.tap(find.byIcon(Icons.outlined_flag_rounded).first);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text(s.t('iv_marked_title')), findsOneWidget);
    expect(find.byIcon(Icons.outlined_flag_rounded), findsOneWidget);

    // Izoh yozamiz — biroz kutib bazaga saqlanadi va ro'yxatda ko'rinadi.
    await tester.enterText(find.byType(TextField), 'Collisions: chaining vs open addressing');
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    final items = (await tester.runAsync(() => state.repo.interviewItems(id)))!;
    expect(items[0].starred, isTrue);
    expect(items[0].note, 'Collisions: chaining vs open addressing');
    expect(items[1].starred, isFalse);
    expect(find.text('Collisions: chaining vs open addressing'), findsNWidgets(2)); // maydon + ro'yxat
    expect(state.interviews.first.marked, 1);

    // "Belgilangan" filtri faqat belgilangan savolni ko'rsatadi.
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.textContaining(s.t('iv_filter_marked'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reverse a linked list'), findsNothing);
  });

  test('marks survive re-segmentation', () async {
    final (state, id) = await setup();
    final repo = state.repo;
    final items = await repo.interviewItems(id);
    await repo.updateItemMarks(items[1].id, starred: true, note: 'practice this', highlights: ['prev, cur, next']);
    // Qayta tahlil: savollar biroz boshqa vaqtda va tartibda.
    await repo.replaceInterviewItems(id, [
      (start: 5.0, end: 30.0, question: {'question': 'Intro'}),
      (start: 12.0, end: 60.0, question: {'question': 'What is a hash map?'}),
      (start: 75.0, end: 200.0, question: {'question': 'Reverse a linked list'}),
    ]);
    final fresh = await repo.interviewItems(id);
    expect(fresh.map((i) => i.starred), [false, false, true]);
    expect(fresh[2].note, 'practice this');
    expect(fresh[2].highlights, ['prev, cur, next']);
    expect((await repo.interview(id))!.marked, 1);
  });
}
