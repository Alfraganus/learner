import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class VideoToolException implements Exception {
  VideoToolException(this.code, [this.detail = '']);

  /// Matn kaliti (strings): masalan `iv_err_ytdlp_missing`.
  final String code;
  final String detail;
  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

/// Video ma'lumoti (yt-dlp -J).
class VideoInfo {
  VideoInfo(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id'] ?? ''}';
  String get title => '${raw['title'] ?? ''}';
  String get channel => '${raw['channel'] ?? raw['uploader'] ?? ''}';
  int get duration => (raw['duration'] as num?)?.round() ?? 0;
  String? get language => (raw['language'] as String?)?.split('-').first;
  String get thumbnail => '${raw['thumbnail'] ?? ''}';

  Map<String, dynamic> get _subs => Map<String, dynamic>.from(raw['subtitles'] as Map? ?? const {})
    ..remove('live_chat');
  Map<String, dynamic> get _auto => Map<String, dynamic>.from(raw['automatic_captions'] as Map? ?? const {});

  /// Eng mos subtitr: avval qo'lda yozilgani (video tilida), keyin avtomatik (asl tildagi).
  ({String key, bool auto})? pickSubtitles() {
    final lang = language;
    final subs = _subs.keys.toList();
    final auto = _auto.keys.toList();
    if (subs.isNotEmpty) {
      if (lang != null) {
        for (final k in subs) {
          if (k == lang || k.startsWith('$lang-')) return (key: k, auto: false);
        }
      }
      // Tili noma'lum: asl tildagi avtomatik subtitr bilan mos keluvchi qo'lda yozilganini olamiz.
      final orig = auto.where((k) => k.endsWith('-orig')).map((k) => k.substring(0, k.length - 5));
      for (final o in orig) {
        for (final k in subs) {
          if (k == o || k.startsWith('$o-')) return (key: k, auto: false);
        }
      }
      if (lang == null) return (key: subs.first, auto: false);
    }
    if (auto.isEmpty) return null;
    if (lang != null) {
      if (auto.contains('$lang-orig')) return (key: '$lang-orig', auto: true);
      if (auto.contains(lang)) return (key: lang, auto: true);
    }
    for (final k in auto) {
      if (k.endsWith('-orig')) return (key: k, auto: true);
    }
    if (auto.contains('en')) return (key: 'en', auto: true);
    return null;
  }
}

/// Subtitrdan bir qator: boshlanish vaqti (soniya) va matn.
class Cue {
  Cue(this.start, this.text);
  final double start;
  final String text;
}

/// Ekran kadri: video ichidagi vaqt (soniya) va fayl.
class Frame {
  Frame(this.time, this.path);
  final double time;
  final String path;
}

/// yt-dlp va ffmpeg bilan ishlash: video ma'lumoti, subtitrlar, yuklab olish va kadrlar.
class VideoTools {
  String ytdlpOverride = '';
  String ffmpegOverride = '';

  /// Kadrlar orasidagi qadam (soniya).
  static const frameStep = 4;

  String? _ytdlp;
  String? _ffmpeg;

  String? get ytdlp => ytdlpOverride.trim().isNotEmpty ? ytdlpOverride.trim() : (_ytdlp ??= _find('yt-dlp'));
  String? get ffmpeg => ffmpegOverride.trim().isNotEmpty ? ffmpegOverride.trim() : (_ffmpeg ??= _find('ffmpeg'));

  void resetResolution() {
    _ytdlp = null;
    _ffmpeg = null;
  }

  static String? _find(String name) {
    final exe = Platform.isWindows ? '$name.exe' : name;
    final dirs = <String>[
      ...(Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':').where((d) => d.isNotEmpty),
    ];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null) {
      dirs.add(p.join(local, 'Microsoft', 'WinGet', 'Links'));
      final py = Directory(p.join(local, 'Programs', 'Python'));
      if (py.existsSync()) {
        for (final d in py.listSync().whereType<Directory>()) {
          dirs.add(p.join(d.path, 'Scripts'));
        }
      }
    }
    final home = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home != null) dirs.add(p.join(home, '.local', 'bin'));
    if (!Platform.isWindows) dirs.addAll(['/usr/local/bin', '/opt/homebrew/bin', '/usr/bin']);
    for (final d in dirs) {
      final f = File(p.join(d, exe));
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  String _need(String? exe, String code) {
    if (exe == null || exe.isEmpty) throw VideoToolException(code);
    return exe;
  }

  Future<ProcessResult> _run(String exe, List<String> args, {Duration timeout = const Duration(minutes: 5)}) async {
    try {
      return await Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8).timeout(timeout);
    } on ProcessException catch (e) {
      throw VideoToolException('iv_err_tool', '$exe: ${e.message}');
    } on TimeoutException {
      throw VideoToolException('iv_err_tool', '$exe: timeout');
    }
  }

  static String _tail(String s) {
    final lines = s.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    return lines.length <= 4 ? lines.join('\n') : lines.sublist(lines.length - 4).join('\n');
  }

  /// YouTube havolasi bo'yicha video ma'lumoti.
  Future<VideoInfo> info(String url) async {
    final exe = _need(ytdlp, 'iv_err_ytdlp_missing');
    final r = await _run(exe, ['-J', '--no-playlist', '--no-warnings', url], timeout: const Duration(minutes: 2));
    if (r.exitCode != 0) throw VideoToolException('iv_err_info', _tail('${r.stderr}'));
    try {
      return VideoInfo(Map<String, dynamic>.from(jsonDecode('${r.stdout}') as Map));
    } catch (_) {
      throw VideoToolException('iv_err_info', _tail('${r.stdout}'));
    }
  }

  /// Subtitrlarni yuklab olib, vaqtli qatorlarga aylantiradi.
  Future<List<Cue>> subtitles(String url, VideoInfo info, String dir) async {
    final exe = _need(ytdlp, 'iv_err_ytdlp_missing');
    final pick = info.pickSubtitles();
    if (pick == null) throw VideoToolException('iv_err_no_subs');
    await Directory(dir).create(recursive: true);
    final r = await _run(exe, [
      '--skip-download',
      '--no-playlist',
      '--no-warnings',
      pick.auto ? '--write-auto-subs' : '--write-subs',
      '--sub-langs', pick.key,
      '--sub-format', 'json3',
      '-o', p.join(dir, 'sub'),
      url,
    ]);
    final f = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('sub.') && f.path.endsWith('.json3'))
        .firstOrNull;
    if (f == null) throw VideoToolException('iv_err_no_subs', _tail('${r.stderr}'));
    final cues = parseJson3(await f.readAsString());
    if (cues.isEmpty) throw VideoToolException('iv_err_no_subs');
    return cues;
  }

  /// YouTube json3 subtitrini o'qiladigan qatorlarga aylantiradi (~gap yoki ~12 soniya).
  static List<Cue> parseJson3(String json) {
    final data = jsonDecode(json) as Map;
    final words = <Cue>[];
    for (final e in (data['events'] as List? ?? const [])) {
      if (e is! Map || e['segs'] is! List) continue;
      final t0 = (e['tStartMs'] as num? ?? 0).toDouble();
      var first = true;
      for (final sg in e['segs'] as List) {
        if (sg is! Map) continue;
        var t = '${sg['utf8'] ?? ''}'.replaceAll('\n', ' ');
        if (t.trim().isEmpty) continue;
        // Yangi hodisaning birinchi so'zi oldingisiga yopishmasin.
        if (first && !t.startsWith(' ')) t = ' $t';
        first = false;
        final off = (sg['tOffsetMs'] as num? ?? 0).toDouble();
        words.add(Cue((t0 + off) / 1000, t));
      }
    }
    final out = <Cue>[];
    var buf = StringBuffer();
    double? start;
    var lastT = 0.0;
    void flush() {
      final s = buf.toString().trim();
      if (s.isNotEmpty) out.add(Cue(start ?? 0, s.replaceAll(RegExp(r'\s+'), ' ')));
      buf = StringBuffer();
      start = null;
    }

    for (final w in words) {
      // Uzoq pauza yoki 12 soniyadan uzun qator — yangi qatordan boshlaymiz.
      if (start != null && (w.start - start! >= 12 || w.start - lastT > 4)) flush();
      start ??= w.start;
      lastT = w.start;
      buf.write(w.text);
      final s = buf.toString().trim();
      final sentenceEnd = RegExp(r'[.!?…]$').hasMatch(s);
      if ((sentenceEnd && s.length > 40) || s.length > 220) flush();
    }
    flush();
    return out;
  }

  /// Videoni (faqat tasvir, ≤720p) yuklab oladi. [onProgress] 0..1.
  Future<String> downloadVideo(String url, String dir, {void Function(double)? onProgress}) async {
    final exe = _need(ytdlp, 'iv_err_ytdlp_missing');
    await Directory(dir).create(recursive: true);
    final out = p.join(dir, 'video.%(ext)s');
    final Process proc;
    try {
      proc = await Process.start(exe, [
        '--no-playlist',
        '--no-warnings',
        '--newline',
        '-f', 'bv*[height<=720][ext=mp4]/bv*[height<=720]/b[height<=720]/bv*/b',
        '-o', out,
        url,
      ]);
    } on ProcessException catch (e) {
      throw VideoToolException('iv_err_tool', e.message);
    }
    final err = StringBuffer();
    final pct = RegExp(r'\[download\]\s+([\d.]+)%');
    final outDone = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      final m = pct.firstMatch(l);
      if (m != null) onProgress?.call((double.tryParse(m.group(1)!) ?? 0) / 100);
    }).asFuture<void>();
    final errDone = proc.stderr.transform(utf8.decoder).listen(err.write).asFuture<void>();
    final code = await proc.exitCode.timeout(const Duration(hours: 2), onTimeout: () {
      proc.kill();
      return -1;
    });
    await outDone.catchError((_) {});
    await errDone.catchError((_) {});
    final f = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('video.') && !f.path.endsWith('.part'))
        .firstOrNull;
    if (code != 0 || f == null) throw VideoToolException('iv_err_download', _tail(err.toString()));
    return f.path;
  }

  /// Har [frameStep] soniyada bitta kadr; deyarli bir xil ketma-ket kadrlar tashlanadi.
  Future<List<Frame>> extractFrames(String video, String dir) async {
    final exe = _need(ffmpeg, 'iv_err_ffmpeg_missing');
    final d = Directory(dir);
    if (d.existsSync()) d.deleteSync(recursive: true);
    d.createSync(recursive: true);
    final r = await _run(
        exe,
        [
          '-hide_banner', '-loglevel', 'error',
          '-i', video,
          '-vf', 'fps=1/$frameStep,mpdecimate=hi=64*40:lo=64*16:frac=0.2,scale=\'min(1280,iw)\':-2',
          '-fps_mode', 'vfr',
          '-frame_pts', '1',
          '-q:v', '4',
          p.join(dir, 'f_%06d.jpg'),
        ],
        timeout: const Duration(hours: 1));
    if (r.exitCode != 0) throw VideoToolException('iv_err_frames', _tail('${r.stderr}'));
    return listFrames(dir);
  }

  /// Papkadagi kadrlar (fayl nomidagi raqam × qadam = vaqt).
  static List<Frame> listFrames(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final re = RegExp(r'f_(\d+)\.jpg$');
    final out = <Frame>[];
    for (final f in d.listSync().whereType<File>()) {
      final m = re.firstMatch(p.basename(f.path));
      if (m != null) out.add(Frame(int.parse(m.group(1)!) * frameStep.toDouble(), f.path));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }
}
