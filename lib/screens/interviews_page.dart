import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/interview.dart';
import '../services/interview_prompts.dart';
import '../services/interview_service.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import 'interview_screen.dart';

/// Intervyular ro'yxati: YouTube havolasini qo'shish va tahlillarni ochish.
class InterviewsPage extends StatelessWidget {
  const InterviewsPage({super.key});

  static Future<void> addDialog(BuildContext context) async {
    final app = context.app;
    final s = app.s;
    final ctrl = TextEditingController();
    String? error;
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        final p = ctx.pal;
        void submit() {
          final u = InterviewService.normalizeUrl(ctrl.text);
          if (u == null) {
            setState(() => error = s.t('iv_bad_url'));
            return;
          }
          Navigator.pop(ctx, u);
        }

        return AlertDialog(
          title: Text(s.t('iv_add_title'), style: display(ctx, size: 20)),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('iv_add_body'), style: TextStyle(color: p.inkSoft, height: 1.45)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  hintText: s.t('iv_add_hint'),
                  prefixIcon: Icon(Icons.smart_display_outlined, color: p.danger),
                  errorText: error,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
            FilledButton.icon(
              onPressed: submit,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(s.t('iv_add_go')),
            ),
          ],
        );
      }),
    );
    if (url == null || !context.mounted) return;
    final id = await app.addInterview(url);
    if (context.mounted) openInterview(context, id);
  }

  static void openInterview(BuildContext context, int id) {
    final app = context.app;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => InterviewScreen(interviewId: id)))
        .then((_) => app.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = context.watch<AppState>();
    final s = app.s;
    final list = app.interviews;
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(48, 44, 48, 0),
        sliver: SliverToBoxAdapter(
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Eyebrow('YouTube'),
                const SizedBox(height: 8),
                Text(s.t('iv_title'), style: serif(context, size: 42, weight: FontWeight.w700, height: 1.1)),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Text(s.t('iv_sub'), style: TextStyle(color: p.inkSoft, height: 1.5, fontSize: 15)),
                ),
              ]),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () => addDialog(context),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(s.t('iv_add')),
            ),
          ]),
        ),
      ),
      if (list.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Hoverable(
              onTap: () => addDialog(context),
              radius: 24,
              border: p.border,
              padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 56),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.record_voice_over_outlined, size: 40, color: p.muted),
                const SizedBox(height: 14),
                Text(s.t('iv_empty'), style: display(context, size: 18)),
                const SizedBox(height: 4),
                Text(s.t('iv_empty_body'), style: TextStyle(color: p.muted)),
              ]),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(48, 28, 48, 48),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380,
              mainAxisExtent: 352,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _InterviewCard(iv: list[i]),
              childCount: list.length,
            ),
          ),
        ),
    ]);
  }
}

class _InterviewCard extends StatelessWidget {
  const _InterviewCard({required this.iv});
  final Interview iv;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.s;
    final app = context.app;
    final busy = app.interviewsSvc.isActive(iv.id) || iv.status == InterviewStatus.processing;
    return Hoverable(
      onTap: () => InterviewsPage.openInterview(context, iv.id),
      radius: 18,
      border: p.border,
      color: p.surface,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              Container(color: p.surfaceAlt),
              if (iv.thumbnailUrl != null)
                Image.network(iv.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
              if (iv.duration > 0)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                    child: Text(InterviewPrompts.mmss(iv.duration.toDouble()),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(iv.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.3, color: p.ink)),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 20, color: p.muted),
                  onSelected: (v) async {
                    if (v == 'delete' && await confirm(context, s.t('iv_delete_q'))) {
                      await app.deleteInterview(iv.id);
                    }
                  },
                  itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(s.t('delete')))],
                ),
              ]),
              if ((iv.channel ?? '').isNotEmpty)
                Text(iv.channel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
              const Spacer(),
              if (iv.isError)
                Text(translateStatus(s, iv.statusMessage),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.danger, fontSize: 12.5))
              else if (busy) ...[
                Text(translateStatus(s, iv.statusMessage),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.inkSoft, fontSize: 12.5)),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: iv.progress, minHeight: 4, backgroundColor: p.surfaceAlt),
                  ),
                ),
              ] else
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ScoreChip(icon: Icons.check_circle_rounded, color: p.success, n: iv.correct, label: s.t('iv_correct')),
                  ScoreChip(icon: Icons.adjust_rounded, color: p.warm, n: iv.partial, label: s.t('iv_partial')),
                  ScoreChip(icon: Icons.cancel_rounded, color: p.danger, n: iv.wrong, label: s.t('iv_incorrect')),
                  if (iv.marked > 0)
                    ScoreChip(
                        icon: Icons.flag_rounded,
                        color: p.accent,
                        n: iv.marked,
                        label: s.t('iv_marked_n', {'n': iv.marked})),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class ScoreChip extends StatelessWidget {
  const ScoreChip({super.key, required this.icon, required this.color, required this.n, required this.label});
  final IconData icon;
  final Color color;
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text('$n', style: TextStyle(fontWeight: FontWeight.w700, color: p.ink, fontSize: 12.5)),
        ]),
      ),
    );
  }
}
