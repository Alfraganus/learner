import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../db/interview_repo.dart';
import '../db/repository.dart';
import '../models/interview.dart';
import 'claude_service.dart';
import 'interview_prompts.dart';
import 'video_tools.dart';

/// YouTube intervyusini tahlil qilish:
/// ma'lumot → subtitrlar → video va ekran kadrlari → savollarni ajratish → har savol tahlili.
/// Har bosqich natijasi bazada saqlanadi, ilova yopilsa ham ish to'xtagan joyidan davom etadi.
class InterviewService {
  InterviewService(this.repo, this.claude, this.tools, this.onChanged);

  final Repository repo;
  final ClaudeService claude;
  final VideoTools tools;
  final void Function() onChanged;
  String Function() langProvider = () => 'uz';

  final _active = <int>{};
  bool isActive(int id) => _active.contains(id);

  /// Bir savolga yuboriladigan eng ko'p kadrlar soni.
  static const maxFramesPerQuestion = 5;

  String dirOf(int id) => p.join(repo.appDb.dataDir.path, 'interviews', '$id');
  String framesDirOf(int id) => p.join(dirOf(id), 'frames');

  /// YouTube havolasini tekshiradi va bitta video havolasiga keltiradi (null — YouTube emas).
  static String? normalizeUrl(String input) {
    final s = input.trim();
    final uri = Uri.tryParse(s.startsWith('http') ? s : 'https://$s');
    if (uri == null) return null;
    final host = uri.host.toLowerCase().replaceFirst('www.', '').replaceFirst('m.', '');
    String? id;
    if (host == 'youtu.be') {
      id = uri.pathSegments.firstOrNull;
    } else if (host == 'youtube.com' || host == 'music.youtube.com') {
      if (uri.path == '/watch') {
        id = uri.queryParameters['v'];
      } else if (uri.pathSegments.length >= 2 &&
          ['shorts', 'live', 'embed', 'v'].contains(uri.pathSegments.first)) {
        id = uri.pathSegments[1];
      }
    }
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id)) return null;
    return 'https://www.youtube.com/watch?v=$id';
  }

  Future<int> add(String url) async {
    final id = await repo.insertInterview(url, langProvider());
    onChanged();
    unawaited(process(id));
    return id;
  }

  Future<void> resumePending() async {
    for (final id in await repo.interviewsWithStatus(InterviewStatus.processing)) {
      unawaited(process(id));
    }
  }

  /// Savollarni va tahlilni qaytadan (joriy tilda) qilish. Subtitr va kadrlar qayta yuklanmaydi.
  Future<void> reanalyze(int id) async {
    if (_active.contains(id)) return;
    await repo.replaceInterviewItems(id, const []);
    await repo.updateInterview(id, {
      'lang': langProvider(),
      'status': InterviewStatus.processing,
      'status_message': 'iv_step_questions',
      'summary': null,
    });
    onChanged();
    await process(id);
  }

  Future<void> retry(int id) async {
    await repo.updateInterview(id, {'status': InterviewStatus.processing, 'status_message': 'iv_step_info'});
    onChanged();
    await process(id);
  }

  Future<void> delete(int id) async {
    await repo.deleteInterview(id);
    try {
      final d = Directory(dirOf(id));
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
    onChanged();
  }

  Future<void> _step(int id, String key, [double? progress]) async {
    await repo.updateInterview(id, {'status_message': key, 'progress': progress});
    onChanged();
  }

  Future<void> process(int id) async {
    if (_active.contains(id)) return;
    _active.add(id);
    try {
      await _process(id);
    } on VideoToolException catch (e) {
      await repo.updateInterview(id, {
        'status': InterviewStatus.error,
        'status_message': e.detail.isEmpty ? e.code : '${e.code}|${e.detail}',
      });
    } on ClaudeException catch (e) {
      await repo.updateInterview(id, {'status': InterviewStatus.error, 'status_message': 'iv_err_claude|${e.message}'});
    } catch (e) {
      await repo.updateInterview(id, {'status': InterviewStatus.error, 'status_message': 'iv_err_claude|$e'});
    } finally {
      _active.remove(id);
      onChanged();
    }
  }

  Future<void> _process(int id) async {
    var iv = await repo.interview(id);
    if (iv == null) return;
    final lang = iv.lang;
    final dir = dirOf(id);

    // 1) Video ma'lumoti va subtitrlar
    var transcriptJson = await repo.interviewTranscript(id);
    List<Cue> cues;
    if (transcriptJson == null || iv.videoId == null) {
      await _step(id, 'iv_step_info');
      final info = await tools.info(iv.url);
      await repo.updateInterview(id, {
        'video_id': info.id,
        'title': info.title,
        'channel': info.channel,
        'duration': info.duration,
      });
      onChanged();
      await _step(id, 'iv_step_subs');
      cues = await tools.subtitles(iv.url, info, dir);
      transcriptJson = jsonEncode([
        for (final c in cues) [double.parse(c.start.toStringAsFixed(1)), c.text],
      ]);
      await repo.updateInterview(id, {'transcript': transcriptJson});
      iv = (await repo.interview(id))!;
    }
    cues = [
      for (final e in jsonDecode(transcriptJson) as List) Cue((e[0] as num).toDouble(), '${e[1]}'),
    ];

    // 2) Ekran kadrlari (ixtiyoriy: yt-dlp/ffmpeg ishlamasa, faqat matn bilan davom etamiz)
    var frames = VideoTools.listFrames(framesDirOf(id));
    if (frames.isEmpty && tools.ffmpeg != null) {
      try {
        await _step(id, 'iv_step_video', 0);
        var lastPct = -1;
        final video = await tools.downloadVideo(iv.url, dir, onProgress: (x) {
          final pct = (x * 100).floor();
          if (pct != lastPct && pct % 5 == 0) {
            lastPct = pct;
            unawaited(_step(id, 'iv_step_video', x));
          }
        });
        await _step(id, 'iv_step_frames');
        frames = await tools.extractFrames(video, framesDirOf(id));
        try {
          File(video).deleteSync(); // kadrlar olindi — videoning o'zi kerak emas
        } catch (_) {}
      } on VideoToolException catch (e) {
        debugPrint('interview $id: frames skipped — $e');
        frames = const [];
      }
    }

    // 3) Savollarni ajratish
    var items = await repo.interviewItems(id);
    if (items.isEmpty) {
      await _step(id, 'iv_step_questions');
      final overview = _evenly(frames, 10);
      final res = await claude.structured(
        system: InterviewPrompts.system(lang),
        prompt: InterviewPrompts.segmentPrompt(
          title: iv.displayTitle,
          channel: iv.channel ?? '',
          duration: iv.duration,
          transcript: _transcriptText(cues),
          frameCount: overview.length,
          lang: lang,
        ),
        schema: InterviewPrompts.segmentSchema,
        images: [
          for (final f in overview) ClaudeImage(f.path, label: 'Frame at ${InterviewPrompts.mmss(f.time)}'),
        ],
      );
      final qs = <({double start, double end, Map<String, dynamic> question})>[];
      for (final q in (res['questions'] as List? ?? const [])) {
        if (q is! Map) continue;
        final start = (q['start_sec'] as num?)?.toDouble() ?? 0;
        var end = (q['end_sec'] as num?)?.toDouble() ?? start;
        if (end < start) end = start;
        qs.add((
          start: start,
          end: end,
          question: {
            'question': '${q['question'] ?? ''}',
            'question_original': '${q['question_original'] ?? ''}',
            'topic': '${q['topic'] ?? ''}',
            'kind': '${q['kind'] ?? 'other'}',
            'shows_screen': q['shows_screen'] == true,
          },
        ));
      }
      qs.sort((a, b) => a.start.compareTo(b.start));
      if (qs.isEmpty) throw VideoToolException('iv_err_no_questions');
      await repo.replaceInterviewItems(id, qs);
      await repo.updateInterview(id, {
        'summary': jsonEncode({
          'language': '${res['language'] ?? ''}',
          'role': '${res['role'] ?? ''}',
          'summary': '${res['summary'] ?? ''}',
          'frames': frames.length,
        }),
      });
      items = await repo.interviewItems(id);
      iv = (await repo.interview(id))!;
    }

    // 4) Har savol tahlili (parallel; Claude xizmati bir vaqtda 2 tadan ortiq so'rov yubormaydi)
    final todo = items.where((i) => !i.analyzed).toList();
    var done = items.length - todo.length;
    await _step(id, 'iv_step_analyze', done / items.length);
    final role = '${iv.summary?['role'] ?? ''}';
    final errors = <Object>[];
    await Future.wait(todo.map((item) async {
      try {
        final a = await _analyze(iv!, item, items.length, cues, frames, role, lang);
        await repo.saveItemAnalysis(item.id, a);
      } catch (e) {
        errors.add(e);
        return;
      }
      done++;
      await _step(id, 'iv_step_analyze', done / items.length);
    }));
    if (errors.isNotEmpty) throw errors.first;

    await repo.updateInterview(id, {
      'status': InterviewStatus.ready,
      'status_message': null,
      'progress': null,
    });
  }

  Future<Map<String, dynamic>> _analyze(Interview iv, InterviewItem item, int total, List<Cue> cues,
      List<Frame> frames, String role, String lang) async {
    final from = item.start - 15, to = item.end + 10;
    final excerpt = _transcriptText(cues.where((c) => c.start >= from && c.start <= to).toList());
    final useFrames = item.showsScreen || item.kind == 'coding' || item.kind == 'system_design';
    final picked = useFrames
        ? _pickFrames(frames.where((f) => f.time >= item.start - 2 && f.time <= item.end + 4).toList())
        : const <Frame>[];
    final res = await claude.structured(
      system: InterviewPrompts.system(lang),
      prompt: InterviewPrompts.analyzePrompt(
        title: iv.displayTitle,
        role: role,
        no: item.idx + 1,
        total: total,
        question: item.text,
        questionOriginal: item.original,
        kind: item.kind,
        excerpt: excerpt.isEmpty ? '(no speech)' : excerpt,
        frameTimes: [for (final f in picked) f.time],
        lang: lang,
      ),
      schema: InterviewPrompts.analyzeSchema,
      images: [
        for (final f in picked)
          ClaudeImage(f.path, label: 'Frame at ${InterviewPrompts.mmss(f.time)} (time_sec=${f.time.round()})'),
      ],
      webSearch: true,
      background: true,
    );
    return res;
  }

  static String _transcriptText(List<Cue> cues) =>
      cues.map((c) => '[${InterviewPrompts.mmss(c.start)}] ${c.text}').join('\n');

  /// Ro'yxatdan [n] ta teng oraliqdagi element.
  static List<Frame> _evenly(List<Frame> all, int n) {
    if (all.length <= n) return all;
    return [for (var i = 0; i < n; i++) all[(i * (all.length - 1) / (n - 1)).round()]];
  }

  /// Savol vaqtidagi kadrlar: teng oraliqda, oxirgisi (kodning yakuniy holati) albatta kiradi.
  static List<Frame> _pickFrames(List<Frame> inRange) => _evenly(inRange, maxFramesPerQuestion);

  /// [time] ga eng yaqin kadr (UI uchun).
  Frame? frameAt(int interviewId, double time) {
    final fs = VideoTools.listFrames(framesDirOf(interviewId));
    if (fs.isEmpty) return null;
    Frame best = fs.first;
    for (final f in fs) {
      if ((f.time - time).abs() < (best.time - time).abs()) best = f;
    }
    return best;
  }
}
