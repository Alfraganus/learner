import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import 'book_tile.dart';
import 'import_flow.dart';

/// "Javon" — barcha kitoblar kategoriyalar bo'yicha.
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.onOpenBook,
    required this.filter,
    required this.onFilter,
  });
  final void Function(Book) onOpenBook;
  final int? filter;
  final ValueChanged<int?> onFilter;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = context.pal;
    var books = app.booksIn(widget.filter);
    if (_q.trim().isNotEmpty) {
      final q = _q.toLowerCase();
      books = books
          .where((b) =>
              b.title.toLowerCase().contains(q) || (b.author ?? '').toLowerCase().contains(q))
          .toList();
    }

    Widget chip(int? id, String label, int count, {Category? cat}) {
      final sel = widget.filter == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Hoverable(
          onTap: () => widget.onFilter(id),
          radius: 999,
          color: sel ? p.ink : p.surface,
          hoverColor: sel ? p.ink : p.surfaceAlt,
          border: sel ? p.ink : p.border,
          padding: EdgeInsets.fromLTRB(16, 9, cat != null ? 6 : 16, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: sel ? p.bg : p.ink)),
              const SizedBox(width: 8),
              Text('$count',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: sel ? p.bg.withValues(alpha: 0.6) : p.muted)),
              if (cat != null)
                SizedBox(
                  height: 22,
                  width: 26,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    tooltip: '',
                    iconSize: 16,
                    icon: Icon(Icons.more_vert_rounded, color: sel ? p.bg : p.muted),
                    onSelected: (v) async {
                      if (v == 'rename') {
                        final name = await promptText(context, title: s.t('rename'), initial: cat.name);
                        if (name != null) await app.renameCategory(cat.id, name);
                      } else if (v == 'delete') {
                        if (await confirm(context, s.t('delete_category_q', {'t': cat.name}))) {
                          if (widget.filter == cat.id) widget.onFilter(null);
                          await app.deleteCategory(cat.id);
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'rename', child: Text(s.t('rename'))),
                      PopupMenuItem(value: 'delete', child: Text(s.t('delete'))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

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
                      Eyebrow(s.t('books_count', {'n': app.allBooks.length})),
                      const SizedBox(height: 8),
                      Text(s.t('nav_library'),
                          style: serif(context, size: 42, weight: FontWeight.w700, height: 1.1)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: s.t('search_books'),
                      prefixIcon: Icon(Icons.search_rounded, color: p.muted),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => ImportFlow.pick(context, preferredCategory: widget.filter),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(s.t('add_book')),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(48, 28, 48, 0),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              children: [
                chip(null, s.t('all_books'), app.allBooks.length),
                for (final c in app.categories) chip(c.id, c.name, c.bookCount, cat: c),
                chip(-1, s.t('uncategorized'), app.booksIn(-1).length),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Hoverable(
                    onTap: () async {
                      final name = await promptText(context,
                          title: s.t('add_category'), label: s.t('category_name'));
                      if (name != null) {
                        final id = await app.addCategory(name);
                        if (id != null) widget.onFilter(id);
                      }
                    },
                    radius: 999,
                    border: p.border,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_rounded, size: 18, color: p.accent),
                      const SizedBox(width: 4),
                      Text(s.t('add_category'),
                          style: TextStyle(color: p.accent, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (books.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Hoverable(
                onTap: () => ImportFlow.pick(context, preferredCategory: widget.filter),
                radius: 24,
                border: p.border,
                padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 56),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, size: 40, color: p.muted),
                    const SizedBox(height: 14),
                    Text(s.t('no_books'), style: display(context, size: 18)),
                    const SizedBox(height: 4),
                    Text(s.t('drop_hint2'), style: TextStyle(color: p.muted)),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(48, 28, 48, 48),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisExtent: 364,
                crossAxisSpacing: 28,
                mainAxisSpacing: 28,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => LayoutBuilder(
                  builder: (ctx, c) => BookTile(
                    book: books[i],
                    coverWidth: c.maxWidth,
                    onOpen: () => widget.onOpenBook(books[i]),
                  ),
                ),
                childCount: books.length,
              ),
            ),
          ),
      ],
    );
  }
}
