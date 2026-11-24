import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/web_source.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';

/// PDF qo'shish oqimi: fayl tanlash yoki tashlash -> kategoriya -> import.
class ImportFlow {
  /// [preferredCategory]: null = so'rash, -1 = kategoriyasiz, aks holda o'sha kategoriya.
  static Future<void> importPaths(BuildContext context, List<String> paths,
      {int? preferredCategory}) async {
    final app = context.app;
    final s = app.s;
    final pdfs = paths.where((p) => p.toLowerCase().endsWith('.pdf')).toList();
    if (pdfs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('not_pdf'))));
      return;
    }
    int? categoryId;
    if (preferredCategory == null) {
      final picked = await chooseCategory(context);
      if (picked == null) return;
      categoryId = picked == -1 ? null : picked;
    } else {
      categoryId = preferredCategory == -1 ? null : preferredCategory;
    }
    for (final p in pdfs) {
      await app.importPdf(p, categoryId);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('import_started', {'n': pdfs.length}))));
    }
  }

  static Future<void> pick(BuildContext context, {int? preferredCategory}) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (file?.path == null || !context.mounted) return;
    await importPaths(context, [file!.path!], preferredCategory: preferredCategory);
  }

  /// Veb-sahifa havolasi: tekshirish → "shu sahifa" yoki "butun bo'lim" → kategoriya → import.
  static Future<void> pickLink(BuildContext context, {int? preferredCategory}) async {
    final app = context.app;
    final s = app.s;
    final ctrl = TextEditingController();
    final res = await showDialog<({String url, String scope, String title})>(
      context: context,
      builder: (ctx) => _LinkDialog(ctrl: ctrl),
    );
    if (res == null || !context.mounted) return;
    int? categoryId;
    if (preferredCategory == null) {
      final picked = await chooseCategory(context);
      if (picked == null) return;
      categoryId = picked == -1 ? null : picked;
    } else {
      categoryId = preferredCategory == -1 ? null : preferredCategory;
    }
    await app.importUrl(res.url, res.scope, categoryId, title: res.title);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('import_started', {'n': 1}))));
    }
  }

  /// -1 = kategoriyasiz, null = bekor qilindi.
  static Future<int?> chooseCategory(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        final p = ctx.pal;
        Widget option(IconData icon, String label, VoidCallback onTap, {Color? color}) => Hoverable(
              onTap: onTap,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(icon, size: 20, color: color ?? p.inkSoft),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(label,
                        style: TextStyle(fontWeight: FontWeight.w600, color: color ?? p.ink))),
              ]),
            );
        return AlertDialog(
          title: Text(s.t('choose_category'), style: display(ctx, size: 20)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in app.categories)
                  option(Icons.folder_open_rounded, c.name, () => Navigator.pop(ctx, c.id)),
                option(Icons.inbox_outlined, s.t('uncategorized'), () => Navigator.pop(ctx, -1)),
                const SizedBox(height: 6),
                option(Icons.add_rounded, s.t('add_category'), () async {
                  final name =
                      await promptText(ctx, title: s.t('add_category'), label: s.t('category_name'));
                  if (name == null || name.trim().isEmpty) return;
                  final id = await app.addCategory(name);
                  if (ctx.mounted) Navigator.pop(ctx, id ?? -1);
                }, color: p.accent),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.ctrl});
  final TextEditingController ctrl;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  bool _checking = false;
  String? _error;
  WebProbe? _probe;
  String _scope = 'section';

  Future<void> _check() async {
    final s = context.sr;
    final u = WebSource.parseUrl(widget.ctrl.text);
    if (u == null) {
      setState(() => _error = s.t('web_bad_url'));
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
      _probe = null;
    });
    try {
      final pr = await WebSource().probe(u);
      if (!mounted) return;
      setState(() {
        _probe = pr;
        _scope = pr.hasSection ? 'section' : 'page';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '${s.t('web_bad_url')} ($e)');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final pr = _probe;
    Widget option(String value, IconData icon, String title, String sub) => RadioListTile<String>(
          value: value,
          contentPadding: EdgeInsets.zero,
          secondary: Icon(icon, color: p.accent),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub, style: TextStyle(color: p.muted, fontSize: 13)),
        );
    return AlertDialog(
      title: Text(s.t('web_title'), style: display(context, size: 20)),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.t('web_body'), style: TextStyle(color: p.inkSoft, height: 1.45)),
          const SizedBox(height: 16),
          TextField(
            controller: widget.ctrl,
            autofocus: true,
            onSubmitted: (_) => _check(),
            onChanged: (_) {
              if (_probe != null) setState(() => _probe = null);
            },
            decoration: InputDecoration(
              hintText: s.t('web_hint'),
              prefixIcon: Icon(Icons.public_rounded, color: p.accent),
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          if (_checking) ...[
            const SizedBox(height: 16),
            Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text(s.t('web_checking'), style: TextStyle(color: p.muted)),
            ]),
          ],
          if (pr != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.article_outlined, color: p.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(pr.page.title, style: TextStyle(fontWeight: FontWeight.w700, color: p.ink)),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _scope,
              onChanged: (v) => setState(() => _scope = v ?? _scope),
              child: Column(children: [
                option('page', Icons.description_outlined, s.t('web_scope_page'), s.t('web_scope_page_sub')),
                if (pr.hasSection)
                  option('section', Icons.library_books_outlined,
                      s.t('web_scope_section', {'n': pr.sectionUrls.length}), s.t('web_scope_section_sub')),
              ]),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
        if (pr == null)
          FilledButton(onPressed: _checking ? null : _check, child: Text(s.t('ok')))
        else
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, (
              url: pr.page.url,
              scope: _scope,
              title: _scope == 'page' ? pr.page.title : '${pr.page.title} · ${Uri.parse(pr.page.url).host.replaceFirst('www.', '')}',
            )),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(s.t('web_go')),
          ),
      ],
    );
  }
}
