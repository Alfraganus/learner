import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import 'book_screen.dart';
import 'home_page.dart';
import 'import_flow.dart';
import 'library_page.dart';
import 'settings_page.dart';

/// Asosiy oyna: chapda tor navigatsiya, o'ngda sahifa. PDF'ni istalgan joyga tashlash mumkin.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _page = 0;
  bool _dragging = false;

  /// Javon sahifasida tanlangan kategoriya (null = hammasi, -1 = kategoriyasiz).
  int? _libraryFilter;

  void openBook(Book b) {
    final app = context.app;
    Navigator.of(context)
        .push(PageRouteBuilder(
          pageBuilder: (_, _, _) => BookScreen(bookId: b.id),
          transitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: (_, a, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ))
        .then((_) => app.refresh());
  }

  void openLibrary(int? category) => setState(() {
        _libraryFilter = category;
        _page = 1;
      });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final pages = [
      HomePage(onOpenBook: openBook, onOpenLibrary: openLibrary),
      LibraryPage(
        onOpenBook: openBook,
        filter: _libraryFilter,
        onFilter: (f) => setState(() => _libraryFilter = f),
      ),
      const SettingsPage(),
    ];

    return Scaffold(
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (d) {
          setState(() => _dragging = false);
          ImportFlow.importPaths(
            context,
            d.files.map((f) => f.path).toList(),
            preferredCategory: _page == 1 ? _libraryFilter : null,
          );
        },
        child: Stack(
          children: [
            Row(
              children: [
                _Rail(page: _page, onPage: (i) => setState(() => _page = i)),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(key: ValueKey(_page), child: pages[_page]),
                  ),
                ),
              ],
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _dragging ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  color: p.bg.withValues(alpha: 0.88),
                  alignment: Alignment.center,
                  child: Container(
                    width: 420,
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: p.accent, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                          child: Icon(Icons.file_download_outlined, size: 34, color: p.accent),
                        ),
                        const SizedBox(height: 18),
                        Text(s.t('drop_here'), style: display(context, size: 22)),
                        const SizedBox(height: 6),
                        Text(s.t('drop_sub'),
                            textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.page, required this.onPage});
  final int page;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.watch<AppState>();
    final s = app.s;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget item(int i, IconData icon, IconData activeIcon, String label) {
      final active = page == i;
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 600),
        child: Hoverable(
          onTap: () => onPage(i),
          radius: 14,
          hoverColor: p.onRail.withValues(alpha: 0.08),
          color: active ? p.onRail.withValues(alpha: 0.12) : null,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
            width: 64,
            child: Column(
              children: [
                Icon(active ? activeIcon : icon,
                    size: 22, color: active ? p.onRail : p.onRail.withValues(alpha: 0.55)),
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: active ? p.onRail : p.onRail.withValues(alpha: 0.55),
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 84,
      color: p.rail,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          const LearnerLogo(size: 44),
          const SizedBox(height: 28),
          item(0, Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, s.t('nav_today')),
          const SizedBox(height: 6),
          item(1, Icons.auto_stories_outlined, Icons.auto_stories_rounded, s.t('nav_library')),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: s.t('ui_language'),
            initialValue: app.uiLang,
            onSelected: app.setUiLang,
            position: PopupMenuPosition.over,
            offset: const Offset(70, -40),
            itemBuilder: (_) => [
              for (final c in AppLang.codes)
                PopupMenuItem(
                  value: c,
                  child: Row(children: [
                    SizedBox(
                      width: 30,
                      child: Text(AppLang.short(c),
                          style: TextStyle(fontWeight: FontWeight.w700, color: p.accent, fontSize: 12)),
                    ),
                    Text(AppLang.label(c)),
                    if (c == app.uiLang) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.check_rounded, size: 16, color: p.accent),
                    ],
                  ]),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              child: Column(children: [
                Icon(Icons.language_rounded, size: 21, color: p.onRail.withValues(alpha: 0.6)),
                const SizedBox(height: 2),
                Text(AppLang.short(app.uiLang),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: p.onRail.withValues(alpha: 0.6),
                    )),
              ]),
            ),
          ),
          const SizedBox(height: 2),
          Tooltip(
            message: s.t('theme'),
            child: IconButton(
              onPressed: () => app.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
              icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: p.onRail.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(height: 6),
          item(2, Icons.tune_rounded, Icons.tune_rounded, s.t('settings')),
        ],
      ),
    );
  }
}
