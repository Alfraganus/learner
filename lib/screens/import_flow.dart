import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
