import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import 'book_tile.dart';
import 'import_flow.dart';

/// "Bugun" — o'quv kuni paneli: davom ettirish, statistika va javonlar.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onOpenBook, required this.onOpenLibrary});
  final void Function(Book) onOpenBook;
  final void Function(int? category) onOpenLibrary;

  String _greeting(dynamic s) {
    final h = DateTime.now().hour;
    if (h < 5) return s.t('greet_night');
    if (h < 12) return s.t('greet_morning');
    if (h < 18) return s.t('greet_day');
    return s.t('greet_evening');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = context.pal;
    final now = DateTime.now();
    final months = s.t('months').split(',');
    final dateStr = '${now.day} ${months[now.month - 1]}';

    final shelves = <({int? id, String name, List<Book> books})>[
      for (final c in app.categories)
        if (app.booksIn(c.id).isNotEmpty) (id: c.id, name: c.name, books: app.booksIn(c.id)),
      if (app.booksIn(-1).isNotEmpty)
        (id: -1, name: s.t('uncategorized'), books: app.booksIn(-1)),
    ];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(48, 44, 48, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow('${s.t('nav_today')} · $dateStr'),
                      const SizedBox(height: 8),
                      Text(_greeting(s),
                          style: serif(context, size: 42, weight: FontWeight.w700, height: 1.1)),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => ImportFlow.pick(context),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(s.t('add_book')),
                ),
              ],
            ),
          ),
        ),
        if (app.allBooks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(onPick: () => ImportFlow.pick(context)),
          )
        else ...[
          if (app.lastBook != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(48, 32, 48, 0),
              sliver: SliverToBoxAdapter(
                child: _HeroContinue(book: app.lastBook!, onOpen: () => onOpenBook(app.lastBook!)),
              ),
            ),
          if (app.stats != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(48, 20, 48, 0),
              sliver: SliverToBoxAdapter(child: _StatsRow(stats: app.stats!)),
            ),
          for (final sh in shelves)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(48, 40, 0, 0),
              sliver: SliverToBoxAdapter(
                child: _Shelf(
                  name: sh.name,
                  books: sh.books,
                  onOpenBook: onOpenBook,
                  onSeeAll: () => onOpenLibrary(sh.id),
                  onAdd: () => ImportFlow.pick(context, preferredCategory: sh.id),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 56)),
        ],
        if (app.allBooks.isNotEmpty && shelves.isEmpty)
          SliverToBoxAdapter(child: SizedBox(height: 10, child: ColoredBox(color: p.bg))),
      ],
    );
  }
}

// ------------------------------------------------------------ Davom ettirish
class _HeroContinue extends StatelessWidget {
  const _HeroContinue({required this.book, required this.onOpen});
  final Book book;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = context.pal;
    final fg = p.bg;
    return Container(
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(26),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  p.accent.withValues(alpha: 0.55),
                  p.accent.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Row(
              children: [
                BookCover(title: book.title, author: book.author, width: 116),
                const SizedBox(width: 32),
                Expanded(
                  child: FutureBuilder(
                    future: app.repo.position(book, app.lang),
                    builder: (context, snap) {
                      final pos = snap.data;
                      final where = pos == null
                          ? ''
                          : [
                              s.t('chapter_n', {'n': pos.chapterIdx + 1}),
                              if (pos.sectionIdx != null)
                                s.t('part_of', {'n': pos.sectionIdx! + 1, 'm': pos.sectionCount}),
                            ].join(' · ');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(s.t('continue_where'), color: p.warm),
                          const SizedBox(height: 10),
                          Text(book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: serif(context,
                                  size: 28, weight: FontWeight.w700, color: fg, height: 1.2)),
                          const SizedBox(height: 10),
                          if (pos != null) ...[
                            Text(where,
                                style: TextStyle(
                                    color: fg.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(pos.lessonTitle ?? pos.chapterTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: fg.withValues(alpha: 0.55))),
                          ],
                          const SizedBox(height: 20),
                          Row(children: [
                            SizedBox(
                                width: 260,
                                child: Bar(book.progress, height: 6, color: p.warm)),
                            const SizedBox(width: 14),
                            Text('${(book.progress * 100).round()}%',
                                style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 6),
                            Text('· ${book.doneSections}/${book.totalSections} ${s.t('parts_word')}',
                                style: TextStyle(color: fg.withValues(alpha: 0.55))),
                          ]),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.warm,
                    foregroundColor: const Color(0xFF1D1B16),
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                  ),
                  onPressed: onOpen,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(s.t('continue')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Statistika
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final LearningStats stats;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    final progress = stats.sectionsTotal == 0 ? 0.0 : stats.sectionsDone / stats.sectionsTotal;

    Widget tile({required Widget lead, required String value, required String label, Widget? trail}) =>
        Expanded(
          child: Container(
            height: 104,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                lead,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value, style: display(context, size: 24)),
                      const SizedBox(height: 2),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 13)),
                    ],
                  ),
                ),
                ?trail,
              ],
            ),
          ),
        );

    Widget badge(IconData icon, Color fg, Color bg) => Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: fg, size: 22),
        );

    return Row(
      children: [
        tile(
          lead: badge(Icons.local_fire_department_rounded, p.warm, p.warmSoft),
          value: s.t('days_n', {'n': stats.streak}),
          label: s.t('streak'),
        ),
        const SizedBox(width: 16),
        tile(
          lead: badge(Icons.today_rounded, p.accent, p.accentSoft),
          value: '${stats.doneToday}',
          label: s.t('parts_today'),
          trail: _WeekBars(stats.week),
        ),
        const SizedBox(width: 16),
        tile(
          lead: ProgressRing(value: progress, size: 44, stroke: 4.5, color: p.success),
          value: '${stats.sectionsDone}/${stats.sectionsTotal}',
          label: s.t('parts_learned'),
        ),
        const SizedBox(width: 16),
        tile(
          lead: badge(Icons.emoji_events_outlined, p.success, p.successSoft),
          value: stats.quizAvg == null ? '—' : '${(stats.quizAvg! * 100).round()}%',
          label: s.t('quiz_avg'),
        ),
      ],
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars(this.week);
  final List<int> week;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mx = math.max(1, week.fold<int>(0, math.max));
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < week.length; i++)
            Container(
              width: 6,
              margin: const EdgeInsets.only(left: 3),
              height: 6 + 38 * (week[i] / mx),
              decoration: BoxDecoration(
                color: i == week.length - 1 ? p.accent : (week[i] > 0 ? p.accent.withValues(alpha: 0.4) : p.border),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Javon
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.name,
    required this.books,
    required this.onOpenBook,
    required this.onSeeAll,
    required this.onAdd,
  });
  final String name;
  final List<Book> books;
  final void Function(Book) onOpenBook;
  final VoidCallback onSeeAll;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(name, style: serif(context, size: 24, weight: FontWeight.w700, height: 1.2)),
              const SizedBox(width: 10),
              Text('${books.length}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: onSeeAll, child: Text('${s.t('see_all')} →')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 296,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 48),
            itemCount: books.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 22),
            itemBuilder: (ctx, i) {
              if (i == books.length) return _AddTile(onTap: onAdd);
              return SizedBox(
                width: 148,
                child: BookTile(book: books[i], onOpen: () => onOpenBook(books[i]), coverWidth: 148),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    return Align(
      alignment: Alignment.topCenter,
      child: Hoverable(
        onTap: onTap,
        radius: 12,
        border: p.border,
        child: SizedBox(
          width: 148,
          height: 148 * 1.48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: p.muted, size: 30),
              const SizedBox(height: 6),
              Text(s.t('add_book'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 240,
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.rotate(
                      angle: -0.18,
                      child: const BookCover(title: 'Algorithms', width: 92, showText: false)),
                  Transform.translate(
                    offset: const Offset(54, 6),
                    child: Transform.rotate(
                        angle: 0.14,
                        child: const BookCover(title: 'Psychology', width: 92, showText: false)),
                  ),
                  Transform.translate(
                      offset: const Offset(-50, 10),
                      child: const BookCover(title: 'History of Art', width: 92, showText: false)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(s.t('empty_title'), style: serif(context, size: 28, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              width: 460,
              child: Text(s.t('empty_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.inkSoft, height: 1.6, fontSize: 15)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(s.t('add_book')),
            ),
            const SizedBox(height: 10),
            Text(s.t('drop_hint2'), style: TextStyle(color: p.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
