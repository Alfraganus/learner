import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';

/// Javondagi kitob: muqova, nom, progress va holat (tayyorlanmoqda / xato).
class BookTile extends StatefulWidget {
  const BookTile({super.key, required this.book, required this.onOpen, this.coverWidth = 160});
  final Book book;
  final VoidCallback onOpen;
  final double coverWidth;

  @override
  State<BookTile> createState() => _BookTileState();
}

class _BookTileState extends State<BookTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = context.pal;
    final b = widget.book;
    final processing = b.status == BookStatus.processing;
    final error = b.status == BookStatus.error;
    final w = widget.coverWidth;

    return MouseRegion(
      cursor: b.isReady ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: b.isReady ? widget.onOpen : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSlide(
              duration: const Duration(milliseconds: 160),
              offset: Offset(0, _hover && b.isReady ? -0.02 : 0),
              child: Stack(
                children: [
                  BookCover(title: b.title, author: b.author, width: w),
                  if (processing || error)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(4), right: Radius.circular(10)),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.55),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (processing)
                                  const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.4, color: Colors.white))
                                else
                                  const Icon(Icons.error_outline_rounded, color: Colors.white),
                                const SizedBox(height: 10),
                                Text(
                                  translateStatus(s, b.statusMessage ?? 'processing'),
                                  textAlign: TextAlign.center,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                                ),
                                if (error) ...[
                                  const SizedBox(height: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                                    onPressed: () => app.retryBook(b.id),
                                    child: Text(s.t('retry')),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (b.isReady && b.progress >= 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: p.success, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: _BookMenu(book: b),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: w,
              child: Text(b.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: p.ink, height: 1.3)),
            ),
            const SizedBox(height: 4),
            if (b.isReady)
              SizedBox(
                width: w,
                child: Row(
                  children: [
                    Expanded(child: Bar(b.progress, height: 4)),
                    const SizedBox(width: 8),
                    Text('${(b.progress * 100).round()}%',
                        style: TextStyle(fontSize: 12, color: p.muted, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            else
              Text(s.t('pages', {'n': b.pageCount}), style: TextStyle(fontSize: 12, color: p.muted)),
          ],
        ),
      ),
    );
  }
}

class _BookMenu extends StatelessWidget {
  const _BookMenu({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final s = app.s;
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        tooltip: '',
        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 18),
        padding: EdgeInsets.zero,
        onSelected: (v) async {
          if (v == 'delete') {
            if (await confirm(context, s.t('delete_book_q', {'t': book.title}))) {
              await app.deleteBook(book);
            }
          } else if (v == 'retry') {
            await app.retryBook(book.id);
          } else if (v.startsWith('move:')) {
            final id = int.parse(v.substring(5));
            await app.moveBook(book.id, id == -1 ? null : id);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(s.t('move_to_category'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          for (final c in app.categories)
            PopupMenuItem(
              value: 'move:${c.id}',
              child: Row(children: [
                Icon(c.id == book.categoryId ? Icons.check_rounded : Icons.folder_open_rounded, size: 18),
                const SizedBox(width: 10),
                Text(c.name),
              ]),
            ),
          PopupMenuItem(
            value: 'move:-1',
            child: Row(children: [
              Icon(book.categoryId == null ? Icons.check_rounded : Icons.inbox_outlined, size: 18),
              const SizedBox(width: 10),
              Text(s.t('uncategorized')),
            ]),
          ),
          const PopupMenuDivider(),
          if (book.status == BookStatus.error)
            PopupMenuItem(value: 'retry', child: Text(s.t('retry'))),
          PopupMenuItem(value: 'delete', child: Text(s.t('delete'))),
        ],
      ),
    );
  }
}
