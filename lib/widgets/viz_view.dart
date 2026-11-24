import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'common.dart';

/// Markdown bo'lagi: oddiy matn yoki ```viz blok (JSON).
class MdPart {
  MdPart.text(this.text) : viz = null;
  MdPart.viz(this.viz, this.text);
  final String text;
  final Map<String, dynamic>? viz;
}

/// Markdown'ni oddiy matn va ```viz bloklariga ajratadi. JSON buzilgan bo'lsa — kod sifatida qoladi.
List<MdPart> splitViz(String md) {
  final lines = md.split('\n');
  final out = <MdPart>[];
  final buf = StringBuffer();
  String? fence; // boshqa kod bloki ichidamizmi
  var i = 0;
  void flush() {
    final t = buf.toString();
    if (t.trim().isNotEmpty) out.add(MdPart.text(t));
    buf.clear();
  }

  while (i < lines.length) {
    final line = lines[i];
    final t = line.trimLeft();
    if (fence == null && RegExp(r'^```+\s*viz\s*$').hasMatch(t)) {
      final body = StringBuffer();
      var j = i + 1;
      while (j < lines.length && !lines[j].trimLeft().startsWith('```')) {
        body.writeln(lines[j]);
        j++;
      }
      Map<String, dynamic>? spec;
      try {
        final v = jsonDecode(body.toString());
        if (v is Map) spec = Map<String, dynamic>.from(v);
      } catch (_) {}
      if (spec != null) {
        flush();
        out.add(MdPart.viz(spec, body.toString()));
      } else {
        buf.writeln('```json');
        buf.write(body);
        buf.writeln('```');
      }
      i = j + 1;
      continue;
    }
    final m = RegExp(r'^(```+|~~~+)').firstMatch(t);
    if (m != null) {
      if (fence == null) {
        fence = m.group(1);
      } else if (t.startsWith(fence)) {
        fence = null;
      }
    }
    buf.writeln(line);
    i++;
  }
  flush();
  return out;
}

/// Matn + vizual bloklar. Oddiy qismlar [Md] bilan chiziladi.
class RichMd extends StatelessWidget {
  const RichMd(this.data,
      {super.key, this.reading = false, this.fontSize, this.imageBuilder, this.selectable = true});
  final String data;
  final bool reading;
  final bool selectable;
  final double? fontSize;
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final parts = splitViz(data);
    if (parts.length == 1 && parts.first.viz == null) {
      return Md(data, reading: reading, fontSize: fontSize, imageBuilder: imageBuilder, selectable: selectable);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in parts)
          p.viz != null
              ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: VizView(spec: p.viz!))
              : Md(p.text, reading: reading, fontSize: fontSize, imageBuilder: imageBuilder, selectable: selectable),
      ],
    );
  }
}

/// Vizual blok: qadam-baqadam, oqim, daraxt yoki ustunli diagramma.
class VizView extends StatelessWidget {
  const VizView({super.key, required this.spec});
  final Map<String, dynamic> spec;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final title = '${spec['title'] ?? ''}'.trim();
    final type = '${spec['type'] ?? ''}';
    final Widget body;
    try {
      body = switch (type) {
        'steps' => _StepsViz(spec: spec),
        'flow' => _FlowViz(spec: spec),
        'tree' => _TreeViz(spec: spec),
        'bars' => _BarsViz(spec: spec),
        _ => Md('```json\n${const JsonEncoder.withIndent('  ').convert(spec)}\n```'),
      };
    } catch (_) {
      return Md('```json\n${const JsonEncoder.withIndent('  ').convert(spec)}\n```');
    }
    final icon = switch (type) {
      'steps' => Icons.slow_motion_video_rounded,
      'flow' => Icons.account_tree_outlined,
      'tree' => Icons.park_outlined,
      'bars' => Icons.bar_chart_rounded,
      _ => Icons.auto_graph_rounded,
    };
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: p.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: p.ink)),
            ),
          ]),
          const SizedBox(height: 14),
          body,
        ],
      ),
    );
  }
}

TextStyle _mono(BuildContext context, {double size = 13.5, Color? color, FontWeight? weight}) => TextStyle(
      fontFamily: Fonts.mono,
      fontFamilyFallback: Fonts.monoFallback,
      fontSize: size,
      color: color ?? context.pal.ink,
      fontWeight: weight,
    );

/// Gorizontal sig'masa — aylantiriladi.
Widget _scrollX(Widget child) => LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: child),
      ),
    );

// ---------------------------------------------------------------- Qadam-baqadam

class _StepsViz extends StatefulWidget {
  const _StepsViz({required this.spec});
  final Map<String, dynamic> spec;
  @override
  State<_StepsViz> createState() => _StepsVizState();
}

class _StepsVizState extends State<_StepsViz> {
  int _i = 0;
  Timer? _timer;

  List<Map> get _steps => [for (final s in (widget.spec['steps'] as List? ?? const [])) if (s is Map) s];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_timer != null) {
      setState(() {
        _timer!.cancel();
        _timer = null;
      });
      return;
    }
    if (_i >= _steps.length - 1) _i = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 1600), (t) {
      if (!mounted) return;
      setState(() {
        if (_i < _steps.length - 1) {
          _i++;
        } else {
          t.cancel();
          _timer = null;
        }
      });
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final steps = _steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final st = steps[_i.clamp(0, steps.length - 1)];
    final array = st['array'] is List ? (st['array'] as List) : null;
    final highlight = {for (final h in (st['highlight'] as List? ?? const [])) if (h is num) h.toInt()};
    final pointers = <int, List<String>>{};
    if (st['pointers'] is Map) {
      (st['pointers'] as Map).forEach((k, v) {
        if (v is num) pointers.putIfAbsent(v.toInt(), () => []).add('$k');
      });
    }
    final vars = st['vars'] is Map ? Map<String, dynamic>.from(st['vars'] as Map) : const <String, dynamic>{};
    final stack = st['stack'] is List ? (st['stack'] as List) : null;
    final output = '${st['output'] ?? ''}';

    Widget cell(int idx, Object? v) {
      final hi = highlight.contains(idx);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(children: [
          Text('$idx', style: TextStyle(fontSize: 10.5, color: p.muted)),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            constraints: const BoxConstraints(minWidth: 44),
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hi ? p.accent : p.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hi ? p.accent : p.border),
            ),
            child: Text('$v', style: _mono(context, size: 15, weight: FontWeight.w700, color: hi ? p.onAccent : p.ink)),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 18,
            child: Text(pointers[idx]?.join(',') ?? '',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.warm)),
          ),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Container(
            key: ValueKey(_i),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: p.warmSoft, borderRadius: BorderRadius.circular(10)),
            child: Text('${st['note'] ?? ''}', style: TextStyle(fontSize: 14.5, height: 1.45, color: p.ink)),
          ),
        ),
        if (array != null) ...[
          const SizedBox(height: 14),
          _scrollX(Row(children: [for (var k = 0; k < array.length; k++) cell(k, array[k])])),
        ],
        if (vars.isNotEmpty || stack != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              for (final e in vars.entries)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.border),
                  ),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${e.key} = ', style: _mono(context, color: p.muted)),
                    TextSpan(text: '${e.value}', style: _mono(context, weight: FontWeight.w700)),
                  ])),
                ),
              if (stack != null)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(color: p.border, width: 2),
                      right: BorderSide(color: p.border, width: 2),
                      bottom: BorderSide(color: p.border, width: 2),
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('stack', style: TextStyle(fontSize: 10.5, color: p.muted)),
                    const SizedBox(height: 3),
                    if (stack.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        child: Text('[ ]', style: _mono(context, size: 12.5, color: p.muted)),
                      ),
                    for (final x in stack.reversed)
                      Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(6)),
                        child: Text('$x', style: _mono(context, size: 12.5)),
                      ),
                  ]),
                ),
            ],
          ),
        ],
        if (output.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
            child: Text('${s.t('viz_output')}:\n$output', style: _mono(context, size: 12.5, color: const Color(0xFFE6E6E6))),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          IconButton(
            tooltip: s.t('viz_prev'),
            onPressed: _i > 0 ? () => setState(() => _i--) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: s.t(_timer != null ? 'viz_pause' : 'viz_play'),
            onPressed: _toggle,
            icon: Icon(_timer != null ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(
            tooltip: s.t('viz_next'),
            onPressed: _i < steps.length - 1 ? () => setState(() => _i++) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(width: 8),
          Text(s.t('viz_step', {'i': _i + 1, 'n': steps.length}), style: TextStyle(color: p.muted, fontSize: 13)),
          const SizedBox(width: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_i + 1) / steps.length,
                minHeight: 4,
                backgroundColor: p.surfaceAlt,
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------- Oqim (flow)

class _FlowViz extends StatelessWidget {
  const _FlowViz({required this.spec});
  final Map<String, dynamic> spec;

  static const nodeW = 156.0, nodeH = 54.0, gapMain = 46.0, gapCross = 26.0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final nodes = <String, Map>{};
    for (final n in (spec['nodes'] as List? ?? const [])) {
      if (n is Map && n['id'] != null) nodes['${n['id']}'] = n;
    }
    final edges = [
      for (final e in (spec['edges'] as List? ?? const []))
        if (e is Map && nodes.containsKey('${e['from']}') && nodes.containsKey('${e['to']}')) e,
    ];
    if (nodes.isEmpty) return const SizedBox.shrink();
    final down = '${spec['direction'] ?? 'down'}' != 'right';

    // Qatlamlar: manbalardan eng uzun yo'l (orqaga qaytuvchi qirralar hisobga olinmaydi).
    final order = nodes.keys.toList();
    final rank = <String, int>{for (final k in order) k: 0};
    final out = <String, List<String>>{};
    for (final e in edges) {
      out.putIfAbsent('${e['from']}', () => []).add('${e['to']}');
    }
    final back = <String>{};
    final state = <String, int>{}; // 1 — yo'lda, 2 — tugadi
    void dfs(String u) {
      state[u] = 1;
      for (final v in out[u] ?? const <String>[]) {
        if (state[v] == 1) {
          back.add('$u>$v');
        } else if (state[v] == null) {
          dfs(v);
        }
      }
      state[u] = 2;
    }

    for (final k in order) {
      if (state[k] == null) dfs(k);
    }
    for (var iter = 0; iter < order.length; iter++) {
      var changed = false;
      for (final e in edges) {
        final a = '${e['from']}', b = '${e['to']}';
        if (back.contains('$a>$b')) continue;
        if (rank[b]! < rank[a]! + 1) {
          rank[b] = rank[a]! + 1;
          changed = true;
        }
      }
      if (!changed) break;
    }
    final layers = <int, List<String>>{};
    for (final k in order) {
      layers.putIfAbsent(rank[k]!, () => []).add(k);
    }
    final maxRank = layers.keys.reduce(math.max);
    final maxCount = layers.values.map((l) => l.length).reduce(math.max);
    final crossSize = maxCount * nodeW + (maxCount - 1) * gapCross;
    final crossSizeR = maxCount * nodeH + (maxCount - 1) * gapCross;
    final pos = <String, Offset>{};
    for (final entry in layers.entries) {
      final l = entry.value;
      for (var i = 0; i < l.length; i++) {
        if (down) {
          final w = l.length * nodeW + (l.length - 1) * gapCross;
          pos[l[i]] = Offset((crossSize - w) / 2 + i * (nodeW + gapCross), entry.key * (nodeH + gapMain));
        } else {
          final h = l.length * nodeH + (l.length - 1) * gapCross;
          pos[l[i]] = Offset(entry.key * (nodeW + gapMain), (crossSizeR - h) / 2 + i * (nodeH + gapCross));
        }
      }
    }
    final size = down
        ? Size(crossSize + 40, (maxRank + 1) * nodeH + maxRank * gapMain)
        : Size((maxRank + 1) * nodeW + maxRank * gapMain + 40, crossSizeR);

    final edgeList = [
      for (final e in edges)
        (from: pos['${e['from']}']!, to: pos['${e['to']}']!, label: '${e['label'] ?? ''}',
          back: back.contains('${e['from']}>${e['to']}')),
    ];

    Widget node(String id) {
      final n = nodes[id]!;
      final kind = '${n['kind'] ?? 'box'}';
      final (Color bg, Color fg, BorderRadius r) = switch (kind) {
        'start' || 'end' => (p.accent, p.onAccent, BorderRadius.circular(nodeH / 2)),
        'decision' => (p.warmSoft, p.ink, BorderRadius.circular(6)),
        'data' => (p.successSoft, p.ink, BorderRadius.circular(14)),
        _ => (p.surfaceAlt, p.ink, BorderRadius.circular(10)),
      };
      return Container(
        width: nodeW,
        height: nodeH,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: r,
          border: Border.all(
            color: kind == 'decision' ? p.warm : (kind == 'data' ? p.success : p.border),
            width: kind == 'decision' ? 1.6 : 1,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (kind == 'decision') ...[Icon(Icons.help_outline_rounded, size: 14, color: p.warm), const SizedBox(width: 4)],
          if (kind == 'data') ...[Icon(Icons.storage_rounded, size: 14, color: p.success), const SizedBox(width: 4)],
          Flexible(
            child: Text('${n['label'] ?? id}',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.25, fontWeight: FontWeight.w600, color: fg)),
          ),
        ]),
      );
    }

    return _scrollX(Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgePainter(edgeList, down, p.muted, TextStyle(fontSize: 11.5, color: p.inkSoft, backgroundColor: p.surface)),
            ),
          ),
          for (final id in nodes.keys) Positioned(left: pos[id]!.dx, top: pos[id]!.dy, child: node(id)),
        ]),
      ),
    ));
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.edges, this.down, this.color, this.labelStyle);
  final List<({Offset from, Offset to, String label, bool back})> edges;
  final bool down;
  final Color color;
  final TextStyle labelStyle;

  static const w = _FlowViz.nodeW, h = _FlowViz.nodeH;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final e in edges) {
      final Offset a, b;
      final path = Path();
      if (e.back) {
        // Orqaga qaytish: yon tomondan aylanib o'tadi.
        if (down) {
          a = e.from + const Offset(w, h / 2);
          b = e.to + const Offset(w, h / 2);
          final x = math.max(a.dx, b.dx) + 28;
          path
            ..moveTo(a.dx, a.dy)
            ..cubicTo(x, a.dy, x, b.dy, b.dx, b.dy);
        } else {
          a = e.from + const Offset(w / 2, h);
          b = e.to + const Offset(w / 2, h);
          final y = math.max(a.dy, b.dy) + 24;
          path
            ..moveTo(a.dx, a.dy)
            ..cubicTo(a.dx, y, b.dx, y, b.dx, b.dy);
        }
      } else if (down) {
        a = e.from + const Offset(w / 2, h);
        b = e.to + const Offset(w / 2, 0);
        final my = (a.dy + b.dy) / 2;
        path
          ..moveTo(a.dx, a.dy)
          ..cubicTo(a.dx, my, b.dx, my, b.dx, b.dy);
      } else {
        a = e.from + const Offset(w, h / 2);
        b = e.to + const Offset(0, h / 2);
        final mx = (a.dx + b.dx) / 2;
        path
          ..moveTo(a.dx, a.dy)
          ..cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      }
      canvas.drawPath(path, paint);
      // O'q uchi: oxirgi segment yo'nalishi bo'yicha.
      final metric = path.computeMetrics().lastOrNull;
      if (metric != null) {
        final t1 = metric.getTangentForOffset(metric.length);
        if (t1 != null) {
          final dir = t1.vector / t1.vector.distance;
          final tip = t1.position;
          final left = tip - dir * 9 + Offset(-dir.dy, dir.dx) * 5;
          final right = tip - dir * 9 - Offset(-dir.dy, dir.dx) * 5;
          canvas.drawPath(
            Path()
              ..moveTo(tip.dx, tip.dy)
              ..lineTo(left.dx, left.dy)
              ..lineTo(right.dx, right.dy)
              ..close(),
            Paint()..color = color,
          );
        }
        if (e.label.isNotEmpty) {
          final mid = metric.getTangentForOffset(metric.length / 2)?.position ?? (a + b) / 2;
          final tp = TextPainter(
            text: TextSpan(text: ' ${e.label} ', style: labelStyle),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 140);
          tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) => true;
}

// ---------------------------------------------------------------- Daraxt

class _TNode {
  _TNode(this.label, this.children);
  final String label;
  final List<_TNode> children;
  double x = 0, y = 0, width = 0;
}

class _TreeViz extends StatelessWidget {
  const _TreeViz({required this.spec});
  final Map<String, dynamic> spec;

  static const nodeW = 92.0, nodeH = 40.0, gapX = 14.0, gapY = 44.0;

  static _TNode _parse(Object? m, int depth) {
    if (m is! Map || depth > 12) return _TNode('$m', []);
    return _TNode('${m['label'] ?? ''}', [
      for (final c in (m['children'] as List? ?? const [])) _parse(c, depth + 1),
    ]);
  }

  static double _measure(_TNode n) {
    if (n.children.isEmpty) return n.width = nodeW;
    var w = 0.0;
    for (final c in n.children) {
      w += _measure(c);
    }
    w += gapX * (n.children.length - 1);
    return n.width = math.max(w, nodeW);
  }

  static void _place(_TNode n, double left, int depth) {
    n.y = depth * (nodeH + gapY);
    if (n.children.isEmpty) {
      n.x = left + (n.width - nodeW) / 2;
      return;
    }
    var childrenW = n.children.fold<double>(0, (a, c) => a + c.width) + gapX * (n.children.length - 1);
    var cx = left + (n.width - childrenW) / 2;
    for (final c in n.children) {
      _place(c, cx, depth + 1);
      cx += c.width + gapX;
    }
    n.x = (n.children.first.x + n.children.last.x) / 2;
  }

  static void _walk(_TNode n, void Function(_TNode) f) {
    f(n);
    for (final c in n.children) {
      _walk(c, f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final root = _parse(spec['root'], 0);
    _measure(root);
    _place(root, 0, 0);
    final all = <_TNode>[];
    _walk(root, all.add);
    final highlight = {for (final h in (spec['highlight'] as List? ?? const [])) '$h'};
    final height = all.map((n) => n.y).reduce(math.max) + nodeH;
    return _scrollX(Center(
      child: SizedBox(
        width: root.width,
        height: height,
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _TreePainter(root, p.muted))),
          for (final n in all)
            Positioned(
              left: n.x,
              top: n.y,
              child: Container(
                width: nodeW,
                height: nodeH,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: highlight.contains(n.label) ? p.accent : p.surfaceAlt,
                  borderRadius: BorderRadius.circular(nodeH / 2),
                  border: Border.all(color: highlight.contains(n.label) ? p.accent : p.border),
                ),
                child: Text(n.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: highlight.contains(n.label) ? p.onAccent : p.ink,
                    )),
              ),
            ),
        ]),
      ),
    ));
  }
}

class _TreePainter extends CustomPainter {
  _TreePainter(this.root, this.color);
  final _TNode root;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    void draw(_TNode n) {
      for (final c in n.children) {
        canvas.drawLine(
          Offset(n.x + _TreeViz.nodeW / 2, n.y + _TreeViz.nodeH),
          Offset(c.x + _TreeViz.nodeW / 2, c.y),
          paint,
        );
        draw(c);
      }
    }

    draw(root);
  }

  @override
  bool shouldRepaint(covariant _TreePainter old) => true;
}

// ---------------------------------------------------------------- Ustunlar

class _BarsViz extends StatelessWidget {
  const _BarsViz({required this.spec});
  final Map<String, dynamic> spec;

  static String _fmt(num v) {
    if (v == v.roundToDouble()) {
      final s = v.round().toString();
      return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    }
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final unit = '${spec['unit'] ?? ''}';
    final items = [
      for (final i in (spec['items'] as List? ?? const []))
        if (i is Map && i['value'] is num) (label: '${i['label'] ?? ''}', value: (i['value'] as num).toDouble()),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final max = items.map((i) => i.value.abs()).reduce(math.max);
    final colors = [p.accent, p.warm, p.success, p.danger, p.inkSoft];
    return Column(children: [
      for (var k = 0; k < items.length; k++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(
              width: 130,
              child: Text(items[k].label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final w = max == 0 ? 0.0 : (items[k].value.abs() / max) * (c.maxWidth - 90);
                return Row(children: [
                  Container(
                    width: math.max(w, 3),
                    height: 22,
                    decoration: BoxDecoration(
                      color: colors[k % colors.length],
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('${_fmt(items[k].value)}${unit.isEmpty ? '' : ' $unit'}',
                        overflow: TextOverflow.ellipsis, style: _mono(context, size: 12.5, color: p.inkSoft)),
                  ),
                ]);
              }),
            ),
          ]),
        ),
    ]);
  }
}
