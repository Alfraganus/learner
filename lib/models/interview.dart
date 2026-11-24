import 'dart:convert';

class InterviewStatus {
  static const processing = 'processing';
  static const ready = 'ready';
  static const error = 'error';
}

/// YouTube'dagi intervyu va uning tahlili.
class Interview {
  Interview({
    required this.id,
    required this.url,
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
    required this.lang,
    required this.status,
    required this.statusMessage,
    required this.progress,
    required this.summary,
    required this.createdAt,
    this.itemCount = 0,
    this.correct = 0,
    this.partial = 0,
    this.wrong = 0,
    this.marked = 0,
  });

  final int id;
  final String url;
  final String? videoId;
  final String? title;
  final String? channel;
  final int duration;
  final String lang;
  final String status;
  final String? statusMessage;
  final double? progress;
  final Map<String, dynamic>? summary;
  final int createdAt;
  final int itemCount;
  final int correct;
  final int partial;
  final int wrong;

  /// Foydalanuvchi muhim deb belgilagan savollar soni.
  final int marked;

  bool get isReady => status == InterviewStatus.ready;
  bool get isError => status == InterviewStatus.error;
  String get displayTitle => (title == null || title!.isEmpty) ? url : title!;
  String? get thumbnailUrl => videoId == null ? null : 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

  /// Videoni [sec] soniyadan ochadigan havola.
  String linkAt(double sec) {
    if (videoId == null) return url;
    return 'https://www.youtube.com/watch?v=$videoId&t=${sec.floor()}s';
  }

  factory Interview.fromRow(Map<String, Object?> r) {
    Map<String, dynamic>? summary;
    try {
      final s = r['summary'] as String?;
      if (s != null && s.isNotEmpty) summary = Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {}
    return Interview(
      id: r['id'] as int,
      url: r['url'] as String,
      videoId: r['video_id'] as String?,
      title: r['title'] as String?,
      channel: r['channel'] as String?,
      duration: (r['duration'] as int?) ?? 0,
      lang: r['lang'] as String,
      status: r['status'] as String,
      statusMessage: r['status_message'] as String?,
      progress: (r['progress'] as num?)?.toDouble(),
      summary: summary,
      createdAt: r['created_at'] as int,
      itemCount: (r['item_count'] as int?) ?? 0,
      correct: (r['n_correct'] as int?) ?? 0,
      partial: (r['n_partial'] as int?) ?? 0,
      wrong: (r['n_wrong'] as int?) ?? 0,
      marked: (r['n_marked'] as int?) ?? 0,
    );
  }
}

/// Ekranda ko'ringan narsa (kod, diagramma, slayd…).
class ScreenCapture {
  ScreenCapture({
    required this.time,
    required this.kind,
    required this.language,
    required this.content,
    required this.showImage,
  });
  final double time;
  final String kind;
  final String language;
  final String content;
  final bool showImage;

  factory ScreenCapture.fromJson(Map m) => ScreenCapture(
    time: (m['time_sec'] as num?)?.toDouble() ?? 0,
    kind: '${m['kind'] ?? 'other'}',
    language: '${m['language'] ?? ''}',
    content: '${m['content'] ?? ''}',
    showImage: m['show_image'] == true,
  );
}

class LearnLink {
  LearnLink(this.title, this.url, this.why);
  final String title;
  final String url;
  final String why;
}

/// Intervyudagi bitta savol va uning tahlili.
class InterviewItem {
  InterviewItem({
    required this.id,
    required this.idx,
    required this.start,
    required this.end,
    required this.question,
    required this.analysis,
    this.starred = false,
    this.note = '',
    this.highlights = const [],
  });

  final int id;
  final int idx;
  final double start;
  final double end;

  /// 1-bosqich: savol (question, question_original, topic, kind, shows_screen).
  final Map<String, dynamic> question;

  /// 2-bosqich: tahlil (null — hali tayyor emas).
  final Map<String, dynamic>? analysis;

  /// Foydalanuvchi belgilari: muhim, shaxsiy izoh va matndan belgilangan parchalar.
  final bool starred;
  final String note;
  final List<String> highlights;

  InterviewItem copyWith({bool? starred, String? note, List<String>? highlights}) => InterviewItem(
    id: id,
    idx: idx,
    start: start,
    end: end,
    question: question,
    analysis: analysis,
    starred: starred ?? this.starred,
    note: note ?? this.note,
    highlights: highlights ?? this.highlights,
  );

  /// Belgilaganlarim ro'yxatida ko'rinadimi.
  bool get hasMarks => starred;

  static List<String> decodeHighlights(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final h in jsonDecode(raw) as List) '$h'];
    } catch (_) {
      return const [];
    }
  }

  String get text => '${question['question'] ?? ''}';
  String get original => '${question['question_original'] ?? ''}';
  String get topic => '${question['topic'] ?? ''}';
  String get kind => '${question['kind'] ?? 'other'}';
  bool get showsScreen => question['shows_screen'] == true;

  bool get analyzed => analysis != null;
  String get verdict => '${analysis?['verdict'] ?? ''}';
  String get verdictReason => '${analysis?['verdict_reason'] ?? ''}';
  String get candidateAnswer => '${analysis?['candidate_answer'] ?? ''}';
  String get betterAnswer => '${analysis?['better_answer'] ?? ''}';
  List<String> get keyPoints => [for (final k in (analysis?['key_points'] as List? ?? const [])) '$k'];
  List<ScreenCapture> get screen => [
    for (final s in (analysis?['screen'] as List? ?? const []))
      if (s is Map) ScreenCapture.fromJson(s),
  ];
  List<LearnLink> get resources => [
    for (final r in (analysis?['resources'] as List? ?? const []))
      if (r is Map && '${r['url'] ?? ''}'.startsWith('http'))
        LearnLink('${r['title'] ?? r['url']}', '${r['url']}', '${r['why'] ?? ''}'),
  ];

  factory InterviewItem.fromRow(Map<String, Object?> r) {
    Map<String, dynamic>? an;
    try {
      final a = r['analysis'] as String?;
      if (a != null && a.isNotEmpty) an = Map<String, dynamic>.from(jsonDecode(a) as Map);
    } catch (_) {}
    return InterviewItem(
      id: r['id'] as int,
      idx: r['idx'] as int,
      start: (r['start_sec'] as num).toDouble(),
      end: (r['end_sec'] as num).toDouble(),
      question: Map<String, dynamic>.from(jsonDecode(r['question'] as String) as Map),
      analysis: an,
      starred: r['starred'] == 1,
      note: (r['note'] as String?) ?? '',
      highlights: decodeHighlights(r['highlights'] as String?),
    );
  }
}
