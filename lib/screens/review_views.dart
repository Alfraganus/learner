import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/async_loader.dart';
import '../widgets/common.dart';

Widget _page(BuildContext context, Widget child, {double maxWidth = 780}) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 64),
      child: Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      ),
    );

class _Header extends StatelessWidget {
  const _Header({
    required this.chapter,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onRegenerate,
  });
  final Chapter chapter;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('${s.t('chapter_n', {'n': chapter.idx + 1})} · ${chapter.displayTitle}'),
                const SizedBox(height: 6),
                Text(title, style: serif(context, size: 30, weight: FontWeight.w700, height: 1.2)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: p.muted)),
              ],
            ),
          ),
          if (onRegenerate != null)
            IconButton(
              tooltip: s.t('regenerate'),
              onPressed: onRegenerate,
              icon: Icon(Icons.autorenew_rounded, color: p.muted),
            ),
        ],
      ),
    );
  }
}

// ======================= Bob yakuni =======================
class ChapterEndView extends StatelessWidget {
  const ChapterEndView({
    super.key,
    required this.chapter,
    required this.onQa,
    required this.onQuiz,
    required this.onExercises,
    required this.onNextChapter,
  });
  final Chapter chapter;
  final VoidCallback onQa;
  final VoidCallback onQuiz;
  final VoidCallback onExercises;
  final VoidCallback? onNextChapter;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;

    Widget action(IconData icon, Color color, String title, String sub, VoidCallback onTap) => Expanded(
          child: Hoverable(
            onTap: onTap,
            radius: 22,
            color: p.surface,
            border: p.border,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(height: 18),
                Text(title, style: display(context, size: 18)),
                const SizedBox(height: 6),
                Text(sub, style: TextStyle(color: p.muted, height: 1.45, fontSize: 13.5)),
                const SizedBox(height: 14),
                Icon(Icons.arrow_forward_rounded, color: color, size: 20),
              ],
            ),
          ),
        );

    return _page(
      context,
      Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: p.successSoft, shape: BoxShape.circle),
            child: Icon(Icons.workspace_premium_rounded, size: 42, color: p.success),
          ),
          const SizedBox(height: 22),
          Eyebrow(s.t('chapter_n', {'n': chapter.idx + 1}), color: p.success),
          const SizedBox(height: 8),
          Text(s.t('chapter_finished'),
              style: serif(context, size: 36, weight: FontWeight.w700, height: 1.2)),
          const SizedBox(height: 8),
          Text(chapter.displayTitle,
              textAlign: TextAlign.center, style: TextStyle(color: p.inkSoft, fontSize: 16)),
          const SizedBox(height: 10),
          Text(s.t('chapter_complete'), style: TextStyle(color: p.muted)),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              action(Icons.forum_outlined, p.accent, s.t('review_qa'), s.t('qa_sub'), onQa),
              const SizedBox(width: 16),
              action(Icons.quiz_outlined, p.warm, s.t('review_quiz'), s.t('quiz_sub'), onQuiz),
              const SizedBox(width: 16),
              action(Icons.edit_note_rounded, p.success, s.t('review_exercises'), s.t('ex_sub'),
                  onExercises),
            ],
          ),
          const SizedBox(height: 36),
          if (onNextChapter != null)
            FilledButton.icon(
              onPressed: onNextChapter,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(s.t('next_chapter')),
            )
          else
            Text(s.t('book_done'), style: display(context, size: 20)),
        ],
      ),
    );
  }
}

// ======================= Savol-javob =======================
class QaView extends StatelessWidget {
  const QaView({super.key, required this.book, required this.chapter});
  final Book book;
  final Chapter chapter;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = context.pal;
    return AsyncLoader<List<QaItem>>(
      key: ValueKey('qa-${chapter.id}-${app.lang}'),
      loadingText: s.t('generating'),
      load: (force) => app.content.qa(book, chapter, app.lang, force: force),
      builder: (ctx, items, regen) => _page(
        ctx,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              chapter: chapter,
              title: s.t('review_qa'),
              subtitle: s.t('qa_hint'),
              icon: Icons.forum_outlined,
              color: p.accent,
              onRegenerate: regen,
            ),
            for (var i = 0; i < items.length; i++) _QaCard(index: i, item: items[i]),
          ],
        ),
      ),
    );
  }
}

class _QaCard extends StatefulWidget {
  const _QaCard({required this.index, required this.item});
  final int index;
  final QaItem item;
  @override
  State<_QaCard> createState() => _QaCardState();
}

class _QaCardState extends State<_QaCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _open ? p.accent.withValues(alpha: 0.5) : p.border),
      ),
      child: Column(
        children: [
          Hoverable(
            onTap: () => setState(() => _open = !_open),
            radius: 18,
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.index + 1}'.padLeft(2, '0'),
                    style: display(context, size: 15, color: p.accent)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(widget.item.question,
                      style: serif(context, size: 17.5, weight: FontWeight.w600, height: 1.45)),
                ),
                const SizedBox(width: 12),
                Text(_open ? s.t('hide_answer') : s.t('show_answer'),
                    style: TextStyle(color: p.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded, color: p.accent),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(56, 0, 24, 20),
                    child: Md(widget.item.answer, fontSize: 15.5),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ======================= Quiz =======================
class QuizView extends StatelessWidget {
  const QuizView({super.key, required this.book, required this.chapter, required this.onFinished});
  final Book book;
  final Chapter chapter;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    return AsyncLoader<List<QuizQuestion>>(
      key: ValueKey('quiz-${chapter.id}-${app.lang}'),
      loadingText: s.t('generating'),
      load: (force) => app.content.quiz(book, chapter, app.lang, force: force),
      builder: (ctx, qs, regen) => _QuizBody(
          book: book, chapter: chapter, questions: qs, onRegenerate: regen, onFinished: onFinished),
    );
  }
}

class _QuizBody extends StatefulWidget {
  const _QuizBody({
    required this.book,
    required this.chapter,
    required this.questions,
    required this.onRegenerate,
    required this.onFinished,
  });
  final Book book;
  final Chapter chapter;
  final List<QuizQuestion> questions;
  final VoidCallback onRegenerate;
  final VoidCallback onFinished;

  @override
  State<_QuizBody> createState() => _QuizBodyState();
}

class _QuizBodyState extends State<_QuizBody> {
  late List<int?> _answers;
  int _i = 0;
  bool _finished = false;
  QuizAttempt? _last;

  @override
  void initState() {
    super.initState();
    _answers = List.filled(widget.questions.length, null);
    context.read<AppState>().repo.bestQuizAttempt(widget.chapter.id).then((a) {
      if (mounted) setState(() => _last = a);
    });
  }

  int get _score {
    var c = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      if (_answers[i] == widget.questions[i].correctIndex) c++;
    }
    return c;
  }

  Future<void> _finish() async {
    final app = context.read<AppState>();
    setState(() => _finished = true);
    await app.repo.saveQuizAttempt(
      chapterId: widget.chapter.id,
      bookId: widget.book.id,
      lang: app.lang,
      score: _score,
      total: widget.questions.length,
      answers: _answers,
    );
    widget.onFinished();
  }

  void _restart() => setState(() {
        _answers = List.filled(widget.questions.length, null);
        _i = 0;
        _finished = false;
      });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    final total = widget.questions.length;
    if (total == 0) return ErrorView(s.t('error'), onRetry: widget.onRegenerate);

    return _page(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            chapter: widget.chapter,
            title: s.t('review_quiz'),
            subtitle: _last != null && !_finished
                ? s.t('last_result', {'s': _last!.score, 't': _last!.total})
                : s.t('quiz_hint', {'n': total}),
            icon: Icons.quiz_outlined,
            color: p.warm,
            onRegenerate: widget.onRegenerate,
          ),
          if (_finished) _result(context, total) else _question(context, total),
        ],
      ),
      maxWidth: 720,
    );
  }

  Widget _question(BuildContext context, int total) {
    final s = context.s;
    final p = context.pal;
    final q = widget.questions[_i];
    final answered = _answers[_i] != null;
    final correct = _answers[_i] == q.correctIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress nuqtalari
        Row(
          children: [
            for (var k = 0; k < total; k++)
              Expanded(
                child: Container(
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _answers[k] == null
                        ? (k == _i ? p.ink.withValues(alpha: 0.35) : p.border)
                        : (_answers[k] == widget.questions[k].correctIndex ? p.success : p.danger),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 26),
        Eyebrow(s.t('question_n', {'n': _i + 1, 'm': total}), color: p.warm),
        const SizedBox(height: 10),
        Md(q.question, reading: true, fontSize: 21),
        const SizedBox(height: 22),
        for (var o = 0; o < q.options.length; o++) _option(context, q, o),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !answered
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: correct ? p.successSoft : p.dangerSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: correct ? p.success : p.danger, size: 20),
                        const SizedBox(width: 8),
                        Text(correct ? s.t('correct') : s.t('wrong'),
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: correct ? p.success : p.danger)),
                      ]),
                      const SizedBox(height: 8),
                      Md(q.explanation, fontSize: 14.5),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            if (_i > 0)
              OutlinedButton.icon(
                onPressed: () => setState(() => _i--),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(s.t('prev')),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: !answered
                  ? null
                  : () {
                      if (_i + 1 < total) {
                        setState(() => _i++);
                      } else {
                        _finish();
                      }
                    },
              icon: Icon(_i + 1 < total ? Icons.arrow_forward_rounded : Icons.flag_rounded, size: 18),
              label: Text(_i + 1 < total ? s.t('next') : s.t('submit_quiz')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _option(BuildContext context, QuizQuestion q, int o) {
    final p = context.pal;
    final chosen = _answers[_i];
    final answered = chosen != null;
    final isCorrect = o == q.correctIndex;
    final isChosen = chosen == o;
    Color border = p.border;
    Color bg = p.paper;
    Color badgeBg = p.surfaceAlt;
    Color badgeFg = p.inkSoft;
    if (answered && isCorrect) {
      border = p.success;
      bg = p.successSoft;
      badgeBg = p.success;
      badgeFg = Colors.white;
    } else if (answered && isChosen) {
      border = p.danger;
      bg = p.dangerSoft;
      badgeBg = p.danger;
      badgeFg = Colors.white;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Hoverable(
        onTap: answered ? null : () => setState(() => _answers[_i] = o),
        radius: 16,
        color: bg,
        hoverColor: p.accentSoft,
        border: border,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(9)),
              child: Text(String.fromCharCode(65 + o),
                  style: TextStyle(fontWeight: FontWeight.w800, color: badgeFg)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(q.options[o], style: TextStyle(fontSize: 15.5, height: 1.4, color: p.ink))),
          ],
        ),
      ),
    );
  }

  Widget _result(BuildContext context, int total) {
    final s = context.s;
    final p = context.pal;
    final frac = _score / total;
    final good = frac >= 0.7;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          ProgressRing(
            value: frac,
            size: 132,
            stroke: 10,
            color: good ? p.success : p.warm,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$_score/$total', style: display(context, size: 30)),
              Text('${(frac * 100).round()}%', style: TextStyle(color: p.muted)),
            ]),
          ),
          const SizedBox(height: 22),
          Text(good ? s.t('quiz_great') : s.t('quiz_more'),
              textAlign: TextAlign.center, style: serif(context, size: 24, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(good ? s.t('quiz_great_sub') : s.t('quiz_more_sub'),
              textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
          const SizedBox(height: 24),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (var k = 0; k < total; k++)
              Hoverable(
                onTap: () => setState(() {
                  _finished = false;
                  _i = k;
                }),
                radius: 10,
                color: _answers[k] == widget.questions[k].correctIndex ? p.successSoft : p.dangerSoft,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('${k + 1}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _answers[k] == widget.questions[k].correctIndex ? p.success : p.danger)),
              ),
          ]),
          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: Text(s.t('try_again')),
          ),
        ],
      ),
    );
  }
}

// ======================= Mashqlar =======================
class ExercisesView extends StatelessWidget {
  const ExercisesView({super.key, required this.book, required this.chapter});
  final Book book;
  final Chapter chapter;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = context.pal;
    return AsyncLoader<(List<Exercise>, Map<int, ExerciseAnswer>)>(
      key: ValueKey('ex-${chapter.id}-${app.lang}'),
      loadingText: s.t('generating'),
      load: (force) async {
        final ex = await app.content.exercises(book, chapter, app.lang, force: force);
        final answers = await app.repo.exerciseAnswers(chapter.id, app.lang);
        return (ex, answers);
      },
      builder: (ctx, data, regen) => _page(
        ctx,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              chapter: chapter,
              title: s.t('review_exercises'),
              subtitle: s.t('ex_hint'),
              icon: Icons.edit_note_rounded,
              color: p.success,
              onRegenerate: regen,
            ),
            for (var i = 0; i < data.$1.length; i++)
              _ExerciseCard(
                key: ValueKey('ex-$i-${data.$1[i].title}'),
                chapter: chapter,
                index: i,
                exercise: data.$1[i],
                saved: data.$2[i],
              ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({
    super.key,
    required this.chapter,
    required this.index,
    required this.exercise,
    required this.saved,
  });
  final Chapter chapter;
  final int index;
  final Exercise exercise;
  final ExerciseAnswer? saved;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  late final TextEditingController _ctrl;
  bool _checking = false;
  bool _showHint = false;
  bool _showSolution = false;
  String? _feedback;
  int? _score;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.saved?.answer ?? '');
    _feedback = widget.saved?.feedback;
    _score = widget.saved?.score;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final app = context.read<AppState>();
    if (_ctrl.text.trim().isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final r = await app.content.checkExercise(
        chapter: widget.chapter,
        exercise: widget.exercise,
        index: widget.index,
        answer: _ctrl.text.trim(),
        lang: app.lang,
      );
      _feedback = r.feedback;
      _score = r.score;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    final e = widget.exercise;
    final diff = e.difficulty.toLowerCase();
    final diffColor = switch (diff) {
      'easy' => p.success,
      'hard' => p.danger,
      _ => p.warm,
    };

    Widget toggle(IconData icon, String label, bool on, VoidCallback onTap) => Hoverable(
          onTap: onTap,
          radius: 10,
          color: on ? p.surfaceAlt : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: p.inkSoft),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: p.inkSoft, fontSize: 13)),
          ]),
        );

    Widget box(Color color, Widget child) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          child: child,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(s.t('exercise_n', {'n': widget.index + 1}),
                  style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: diffColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(s.t('difficulty_$diff'),
                    style: TextStyle(color: diffColor, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              const Spacer(),
              if (_score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _score! >= 70 ? p.successSoft : p.dangerSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(s.t('score', {'s': _score!}),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _score! >= 70 ? p.success : p.danger,
                          fontSize: 12.5)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(e.title, style: serif(context, size: 22, weight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 10),
          Md(e.task, fontSize: 15.5),
          const SizedBox(height: 12),
          Row(children: [
            toggle(Icons.tips_and_updates_outlined, s.t('hint'), _showHint,
                () => setState(() => _showHint = !_showHint)),
            const SizedBox(width: 6),
            toggle(Icons.task_alt_rounded, s.t('solution'), _showSolution,
                () => setState(() => _showSolution = !_showSolution)),
          ]),
          if (_showHint) box(p.warmSoft, Md(e.hint, fontSize: 14.5)),
          if (_showSolution) box(p.surfaceAlt, Md(e.solution, fontSize: 14.5)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            minLines: 4,
            maxLines: 18,
            style: TextStyle(fontFamily: Fonts.mono, fontFamilyFallback: Fonts.monoFallback, fontSize: 14, height: 1.5),
            decoration: InputDecoration(hintText: s.t('your_answer')),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.bg))
                    : const Icon(Icons.fact_check_outlined, size: 18),
                label: Text(_checking ? s.t('checking') : s.t('check_answer')),
              ),
            ],
          ),
          if (_error != null) box(p.dangerSoft, SelectableText(_error!)),
          if (_feedback != null && _feedback!.isNotEmpty)
            box(
              p.accentSoft,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.school_outlined, size: 18, color: p.accent),
                  const SizedBox(width: 8),
                  Text(s.t('feedback'), style: TextStyle(fontWeight: FontWeight.w700, color: p.accent)),
                ]),
                const SizedBox(height: 8),
                Md(_feedback!, fontSize: 14.5),
              ]),
            ),
        ],
      ),
    );
  }
}
