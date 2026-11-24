import 'prompts.dart';

/// YouTube intervyularini tahlil qilish uchun promptlar va sxemalar.
class InterviewPrompts {
  static String system(String lang) =>
      'You are a senior software engineer and an experienced technical interviewer and coach. '
      'You analyze recorded job interviews (from YouTube) for a learner who wants to prepare for interviews. '
      'You are precise and honest: you never invent what the candidate said or what was on the screen. '
      'All explanations you write must be in ${Prompts.langName(lang)} '
      '(keep code, identifiers, quotes and the original question text as they are; '
      'for important technical terms give the original term in parentheses the first time).';

  static String mmss(double sec) {
    final s = sec.floor();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(r)}' : '${two(m)}:${two(r)}';
  }

  static String segmentPrompt({
    required String title,
    required String channel,
    required int duration,
    required String transcript,
    required int frameCount,
    required String lang,
  }) =>
      '''
Video: "$title" (channel: $channel, length ${mmss(duration.toDouble())})
${frameCount > 0 ? 'Above are $frameCount frames sampled evenly across the video, so you can see whether the screen shows code, a whiteboard, slides or only faces.\n' : ''}
Below is the full transcript with timestamps ([mm:ss] = time in the video). It comes from auto-generated subtitles, so expect missing punctuation, merged words and no speaker labels — infer who is speaking from context.

Task: find EVERY question asked in this interview, in order.
- A question is anything the interviewer asks the candidate to answer, explain or solve: theory questions, coding problems, system-design tasks, behavioral questions, and substantive follow-ups ("what is the complexity?", "can you optimize it?", "how would it scale?"). Treat a meaningful follow-up as its own question.
- If the video is not a dialogue (e.g. one person reads "top interview questions" and answers them, or solves problems alone), treat each question/problem they pose as a question and their own answer as the candidate's answer.
- Skip small talk, intros, outros, sponsor segments and the host's commentary to viewers.
- "start_sec": when the question starts being asked. "end_sec": when the candidate's answer (including any coding) ends — usually right before the next question. Use seconds from the [mm:ss] marks.
- "question_original": the question as asked, cleaned up, in the original language of the video. For a coding problem, include the full problem statement as given (read it from the screen if it is shown there).
- "question": the same question written clearly in ${Prompts.langName(lang)}.
- "topic": 1-4 words (e.g. "Stack", "HTTP caching", "React state").
- "kind": theory | coding | system_design | behavioral | other.
- "shows_screen": true if, while this question is answered, the screen likely shows code, a diagram, a whiteboard or slides (judge from the frames and from words like "let me write", "as you can see", "here on the screen").

Also return:
- "language": ISO 639-1 code of the spoken language;
- "role": the position/level the interview is for, if known (in ${Prompts.langName(lang)}, may be empty);
- "summary": 2-3 sentences in ${Prompts.langName(lang)} about what this interview covers.

TRANSCRIPT:
$transcript
''';

  static const segmentSchema = {
    'type': 'object',
    'properties': {
      'language': {'type': 'string'},
      'role': {'type': 'string'},
      'summary': {'type': 'string'},
      'questions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'start_sec': {'type': 'number'},
            'end_sec': {'type': 'number'},
            'question_original': {'type': 'string'},
            'question': {'type': 'string'},
            'topic': {'type': 'string'},
            'kind': {
              'type': 'string',
              'enum': ['theory', 'coding', 'system_design', 'behavioral', 'other'],
            },
            'shows_screen': {'type': 'boolean'},
          },
          'required': ['start_sec', 'end_sec', 'question_original', 'question', 'topic', 'kind', 'shows_screen'],
        },
      },
    },
    'required': ['language', 'role', 'summary', 'questions'],
  };

  static String analyzePrompt({
    required String title,
    required String role,
    required int no,
    required int total,
    required String question,
    required String questionOriginal,
    required String kind,
    required String excerpt,
    required List<double> frameTimes,
    required String lang,
  }) =>
      '''
Interview: "$title"${role.isNotEmpty ? ' (role: $role)' : ''}
Question $no of $total (kind: $kind):
"$questionOriginal"
(in the learner's language: "$question")
${frameTimes.isNotEmpty ? '\nAbove are ${frameTimes.length} screen frames captured while this question was answered, at ${frameTimes.map(mmss).join(', ')}. Each frame is labeled with its time.\n' : ''}
Transcript of this part ([mm:ss] = time in the video; auto-generated subtitles, no speaker labels):
"""
$excerpt
"""

Analyze how the candidate answered. Return:
- "candidate_answer": what the candidate actually said and did, faithfully and in order, in ${Prompts.langName(lang)} (Markdown allowed). Include their approach, the steps they took, their final solution and any mistakes. If they wrote code, say so (the code itself goes to "screen"). If there was no answer, return an empty string.
- "screen": everything meaningful that was SHOWN on the screen for this question (code editor, whiteboard, diagram, slides, terminal output), taken from the frames. For code, "content" must be an exact transcription of the code as it appears in the most complete frame (fix nothing, keep indentation), and "language" the programming language. For a diagram, whiteboard or slide, "content" is a clear description in ${Prompts.langName(lang)} (or the exact text on a slide). "time_sec" is the time of the frame you used. "show_image": true if the learner should see the picture itself (diagrams, whiteboards, important slides, and the final state of the code). Return an empty list if nothing relevant was shown (e.g. only faces).
- "verdict": correct | partial | incorrect | no_answer — judge the technical quality of the candidate's answer (partial = right idea but missing important points, has bugs, or suboptimal where an optimal answer was expected).
- "verdict_reason": 1-3 sentences in ${Prompts.langName(lang)} explaining the verdict: what was right, what was wrong or missing.
- "better_answer": in ${Prompts.langName(lang)}, Markdown — the answer a strong candidate would give. If the candidate was not fully correct, correct them explicitly and explain why. For coding questions give clean, correct code in the language the candidate used (fenced code block), explain the idea step by step and give time/space complexity. Where a picture helps (algorithm steps, data flow, a structure), add one visual block as described below.
- "key_points": 2-5 short points to remember for this question (in ${Prompts.langName(lang)}).
- "resources": 2-4 high-quality links to learn and strengthen this topic (official documentation, well-known articles, courses, problem pages such as LeetCode). Use web search to find them, and return ONLY URLs that you actually saw in search results. "why": one short sentence in ${Prompts.langName(lang)} on what the learner gets from the link.

${Prompts.vizGuide}
''';

  static const analyzeSchema = {
    'type': 'object',
    'properties': {
      'candidate_answer': {'type': 'string'},
      'screen': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'time_sec': {'type': 'number'},
            'kind': {
              'type': 'string',
              'enum': ['code', 'diagram', 'whiteboard', 'slide', 'terminal', 'other'],
            },
            'language': {'type': 'string'},
            'content': {'type': 'string'},
            'show_image': {'type': 'boolean'},
          },
          'required': ['time_sec', 'kind', 'language', 'content', 'show_image'],
        },
      },
      'verdict': {
        'type': 'string',
        'enum': ['correct', 'partial', 'incorrect', 'no_answer'],
      },
      'verdict_reason': {'type': 'string'},
      'better_answer': {'type': 'string'},
      'key_points': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'resources': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'url': {'type': 'string'},
            'why': {'type': 'string'},
          },
          'required': ['title', 'url', 'why'],
        },
      },
    },
    'required': [
      'candidate_answer',
      'screen',
      'verdict',
      'verdict_reason',
      'better_answer',
      'key_points',
      'resources',
    ],
  };
}
