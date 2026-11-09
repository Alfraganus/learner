import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../ui/theme.dart';
import 'common.dart';

/// Kitobdagi rasm: PDF sahifasidan kesib chiziladi. Bosilsa — kattalashtirib ko'rish oynasi.
class FigureView extends StatefulWidget {
  const FigureView({super.key, required this.pdfPath, required this.figure});
  final String pdfPath;
  final BookFigure figure;

  @override
  State<FigureView> createState() => _FigureViewState();
}

class _FigureViewState extends State<FigureView> {
  late Future<ui.Image?> _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FigureView old) {
    super.didUpdateWidget(old);
    if (old.figure.label != widget.figure.label || old.pdfPath != widget.pdfPath) _load();
  }

  void _load() {
    _img = context.app.figures.render(widget.pdfPath, widget.figure);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final f = widget.figure;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Hoverable(
        onTap: () => showFigureDialog(context, widget.pdfPath, f),
        radius: 16,
        border: p.border,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rasm har doim oq fonda — qorong'i mavzuda ham kitobdagidek o'qiladi.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(14),
                child: FutureBuilder<ui.Image?>(
                  future: _img,
                  builder: (context, snap) {
                    final img = snap.data;
                    if (img == null) {
                      return SizedBox(
                        height: 180,
                        child: Center(
                          child: snap.connectionState == ConnectionState.done
                              ? Text(s.t('figure_error'), style: TextStyle(color: p.muted))
                              : const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                        ),
                      );
                    }
                    return LayoutBuilder(builder: (context, c) {
                      // 3x chizilgan: tabiiy o'lcham ≈ kitobdagidan biroz kattaroq, lekin kenglikdan oshmaydi.
                      final natural = img.width / 2.2;
                      final w = natural.clamp(0.0, c.maxWidth);
                      return Center(
                        child: SizedBox(
                          width: w,
                          height: w * img.height / img.width,
                          child: RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                        ),
                      );
                    });
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.image_outlined, size: 17, color: p.accent),
                  const SizedBox(width: 8),
                  Text(s.t('figure_n', {'n': f.label}),
                      style: TextStyle(fontWeight: FontWeight.w700, color: p.ink, fontSize: 13.5)),
                  const SizedBox(width: 8),
                  Text('· ${s.t('figure_page', {'n': f.page})}',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  const Spacer(),
                  Icon(Icons.zoom_out_map_rounded, size: 17, color: p.muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showFigureDialog(BuildContext context, String pdfPath, BookFigure f) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) => _FigureDialog(pdfPath: pdfPath, figure: f),
  );
}

class _FigureDialog extends StatefulWidget {
  const _FigureDialog({required this.pdfPath, required this.figure});
  final String pdfPath;
  final BookFigure figure;

  @override
  State<_FigureDialog> createState() => _FigureDialogState();
}

class _FigureDialogState extends State<_FigureDialog> {
  bool _fullPage = false;
  final _tc = TransformationController();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final f = widget.figure;
    final fut = context.app.figures.render(widget.pdfPath, f, fullPage: _fullPage, scale: _fullPage ? 2.5 : 4);
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(
              children: [
                Icon(Icons.image_outlined, color: p.accent, size: 20),
                const SizedBox(width: 10),
                Text(s.t('figure_n', {'n': f.label}), style: display(context, size: 17)),
                const SizedBox(width: 10),
                Text('· ${s.t('figure_page', {'n': f.page})}', style: TextStyle(color: p.muted)),
                const Spacer(),
                Text(s.t('figure_zoom_hint'), style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _fullPage = !_fullPage;
                    _tc.value = Matrix4.identity();
                  }),
                  icon: Icon(_fullPage ? Icons.crop_rounded : Icons.description_outlined, size: 18),
                  label: Text(s.t(_fullPage ? 'figure_only' : 'figure_full_page')),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: Container(
              color: Colors.white,
              child: FutureBuilder<ui.Image?>(
                key: ValueKey(_fullPage),
                future: fut,
                builder: (context, snap) {
                  final img = snap.data;
                  if (img == null) {
                    return Center(
                      child: snap.connectionState == ConnectionState.done
                          ? Text(s.t('figure_error'), style: TextStyle(color: p.muted))
                          : const CircularProgressIndicator(),
                    );
                  }
                  return InteractiveViewer(
                    transformationController: _tc,
                    minScale: 0.5,
                    maxScale: 6,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
