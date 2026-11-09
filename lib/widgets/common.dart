import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';

extension Ctx on BuildContext {
  S get s => watch<AppState>().s;
  S get sr => read<AppState>().s;
  AppState get app => read<AppState>();
}

String translateStatus(S s, String? msg) => msg == null ? '' : s.t(msg);

// ============================================================ Markdown
class Md extends StatelessWidget {
  const Md(this.data, {super.key, this.reading = false, this.fontSize, this.imageBuilder});
  final String data;

  /// Markdown ichidagi rasmlar (masalan, `learner-fig:1-4` — kitobdagi rasm).
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;

  /// O'qish rejimi: serif shrift, kattaroq interval.
  final bool reading;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final theme = Theme.of(context);
    final size = fontSize ?? (reading ? 18.0 : 15.0);
    final body = reading
        ? serif(context, size: size, height: 1.75)
        : TextStyle(fontSize: size, height: 1.6, color: p.ink);
    final mono = TextStyle(
      fontFamily: Fonts.mono,
      fontFamilyFallback: Fonts.monoFallback,
      fontSize: size - 3,
      color: p.ink,
      height: 1.5,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      imageBuilder: imageBuilder,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body,
        listBullet: body,
        tableBody: body.copyWith(fontSize: size - 2),
        tableHead: body.copyWith(fontSize: size - 2, fontWeight: FontWeight.w700),
        strong: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
        em: TextStyle(fontStyle: FontStyle.italic, color: p.inkSoft),
        h1: display(context, size: size + 10),
        h2: display(context, size: size + 6, height: 1.3),
        h3: display(context, size: size + 2, weight: FontWeight.w700, height: 1.35),
        h4: display(context, size: size, weight: FontWeight.w700),
        h2Padding: const EdgeInsets.only(top: 18, bottom: 4),
        h3Padding: const EdgeInsets.only(top: 12, bottom: 2),
        pPadding: const EdgeInsets.only(bottom: 4),
        blockSpacing: reading ? 14 : 10,
        code: mono.copyWith(backgroundColor: p.surfaceAlt),
        codeblockDecoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        codeblockPadding: const EdgeInsets.all(16),
        blockquote: body.copyWith(color: p.inkSoft),
        blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        blockquoteDecoration: BoxDecoration(
          color: p.warmSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: p.warm, width: 3)),
        ),
        tableBorder: TableBorder.all(color: p.border, borderRadius: BorderRadius.circular(8)),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        tableHeadAlign: TextAlign.left,
        horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
        a: TextStyle(color: p.accent, decoration: TextDecoration.underline),
      ),
    );
  }
}

// ============================================================ Holatlar
class LoadingView extends StatefulWidget {
  const LoadingView(this.message, {super.key, this.hint});
  final String message;
  final String? hint;

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = (_c.value - i * 0.18) % 1.0;
                  final s = 0.55 + 0.45 * math.sin(t * math.pi).clamp(0.0, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: 12 * s,
                    height: 12 * s,
                    decoration: BoxDecoration(
                      color: Color.lerp(p.border, p.accent, s)!,
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 22),
            Text(widget.message,
                textAlign: TextAlign.center, style: display(context, size: 18, weight: FontWeight.w600)),
            if (widget.hint != null) ...[
              const SizedBox(height: 6),
              Text(widget.hint!, textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: p.dangerSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 32, color: p.danger),
                const SizedBox(height: 12),
                SelectableText(message, textAlign: TextAlign.center, style: TextStyle(color: p.ink)),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(s.t('retry')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================ Kichik elementlar
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w700,
          color: color ?? context.pal.muted,
        ),
      );
}

/// Aylana progress (foiz bilan).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 44,
    this.stroke = 4,
    this.color,
    this.child,
    this.showLabel = true,
  });
  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0, 1), stroke, color ?? p.accent, p.border),
        child: Center(
          child: child ??
              (showLabel
                  ? Text('${(value * 100).round()}%',
                      style: TextStyle(
                          fontSize: size * 0.26, fontWeight: FontWeight.w700, color: p.ink))
                  : null),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.color, this.track);
  final double v;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, paint..color = track);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color || old.track != track;
}

/// Ingichka progress chizig'i.
class Bar extends StatelessWidget {
  const Bar(this.value, {super.key, this.height = 6, this.color});
  final double value;
  final double height;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: p.border)),
          FractionallySizedBox(
            widthFactor: value.clamp(0, 1),
            child: ColoredBox(color: color ?? p.accent),
          ),
        ]),
      ),
    );
  }
}

/// Bosiladigan, hover effekti bor yuza.
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 16,
    this.color,
    this.hoverColor,
    this.border,
    this.padding,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final Color? hoverColor;
  final Color? border;
  final EdgeInsetsGeometry? padding;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _h && widget.onTap != null
                ? (widget.hoverColor ?? p.surfaceAlt)
                : (widget.color ?? Colors.transparent),
            borderRadius: BorderRadius.circular(widget.radius),
            border: widget.border != null ? Border.all(color: widget.border!) : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ============================================================ Generativ muqova
/// Kitob nomidan "chizilgan" muqova: har kitob o'z rangi va naqshiga ega.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.title, this.author, this.width = 120, this.showText = true});
  final String title;
  final String? author;
  final double width;
  final bool showText;

  static const _pairs = [
    [Color(0xFF2B2D6E), Color(0xFF6C5CE7)],
    [Color(0xFF0F4C5C), Color(0xFF2A9D8F)],
    [Color(0xFF7A2E1E), Color(0xFFE76F51)],
    [Color(0xFF243B2F), Color(0xFF6A994E)],
    [Color(0xFF3D2C5E), Color(0xFFC06C84)],
    [Color(0xFF1B263B), Color(0xFF415A77)],
    [Color(0xFF5C3D0E), Color(0xFFDDA15E)],
    [Color(0xFF14213D), Color(0xFFFCA311)],
    [Color(0xFF3A0CA3), Color(0xFF4CC9F0)],
    [Color(0xFF283618), Color(0xFFBC6C25)],
  ];

  @override
  Widget build(BuildContext context) {
    final h = title.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    final pair = _pairs[h % _pairs.length];
    final pattern = (h ~/ 7) % 4;
    final height = width * 1.48;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(4), right: Radius.circular(10)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: width * 0.12,
              offset: Offset(0, width * 0.05)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _CoverPainter(pair[0], pair[1], pattern, h),
        child: showText
            ? Padding(
                padding: EdgeInsets.fromLTRB(width * 0.14, width * 0.12, width * 0.1, width * 0.1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: width * 0.18, height: 2, color: Colors.white70),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: Fonts.serif,
                        fontFamilyFallback: Fonts.serifFallback,
                        color: Colors.white,
                        fontSize: width * 0.115,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (author != null && author!.isNotEmpty) ...[
                      SizedBox(height: width * 0.04),
                      Text(author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white70, fontSize: width * 0.075)),
                    ],
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.a, this.b, this.pattern, this.seed);
  final Color a;
  final Color b;
  final int pattern;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [a, b],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.012;
    final rnd = math.Random(seed);
    switch (pattern) {
      case 0: // konsentrik aylanalar
        final c = Offset(size.width * (0.6 + rnd.nextDouble() * 0.3), size.height * 0.32);
        for (var i = 1; i < 9; i++) {
          canvas.drawCircle(c, size.width * 0.09 * i, line);
        }
      case 1: // diagonal chiziqlar
        for (var x = -size.height; x < size.width; x += size.width * 0.09) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
        }
      case 2: // nuqtalar to'ri
        final dot = Paint()..color = Colors.white.withValues(alpha: 0.16);
        final step = size.width * 0.1;
        for (var y = step; y < size.height * 0.62; y += step) {
          for (var x = step; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), size.width * 0.012, dot);
          }
        }
      default: // yoylar
        for (var i = 0; i < 5; i++) {
          final r = size.width * (0.3 + i * 0.16);
          canvas.drawArc(Rect.fromCircle(center: Offset(size.width, 0), radius: r), math.pi / 2,
              math.pi / 2, false, line);
        }
    }
    // Kitob umurtqasi soyasi
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * 0.05, size.height),
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.black.withValues(alpha: 0.28),
          Colors.black.withValues(alpha: 0.0),
        ]).createShader(Rect.fromLTWH(0, 0, size.width * 0.05, size.height)),
    );
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.seed != seed;
}

// ============================================================ Dialoglar
Future<String?> promptText(BuildContext context,
    {required String title, String initial = '', String? label}) {
  final ctrl = TextEditingController(text: initial);
  final s = context.sr;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: display(ctx, size: 20)),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(s.t('save'))),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String message) async {
  final s = context.sr;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message, style: const TextStyle(fontSize: 15, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ctx.pal.danger, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s.t('delete')),
        ),
      ],
    ),
  );
  return r ?? false;
}
