import '../l10n/strings.dart';

/// claude -p uchun promptlar va JSON sxemalar.
class Prompts {
  static String langName(String code) => AppLang.promptName(code);

  // ---------------- Kitob tuzilishi ----------------
  static const structureSystem =
      'You are an expert book analyst. You receive a compact digest of a PDF book '
      '(first lines of every page, the PDF outline if present, and the full text of the first pages). '
      'Your job is to split the WHOLE book into chapters using real PDF page numbers. '
      'Always answer only via the structured output.';

  static String structurePrompt({
    required String fileName,
    required int pageCount,
    required String outline,
    required String frontText,
    required String pageHeads,
    required String targetLang,
  }) =>
      '''
File: $fileName
Total PDF pages: $pageCount

Task:
1. Detect the book title, author and the language of the book (ISO 639-1 code).
2. Split the entire book into chapters (top-level logical units: preface/introduction, chapters, appendices, etc.).
   - "start_page" is the 1-based PDF page index where the chapter starts (NOT the printed page number; use the "[p N]" markers below).
   - Chapters must be in ascending order and together must cover the whole book. The first item must start at page 1.
   - Mark purely non-learning parts (cover, copyright page, table of contents, index, blank pages, ads) with "include": false. Everything with real content (preface, introduction, every chapter, appendices, conclusion) must be "include": true. When in doubt, include it.
   - If a chapter is very long (more than ~60 pages) and has clear major sub-parts, you may split it into several chapters named like "3.1 ...".
   - Keep the original chapter titles (with their numbers) in "title".
3. Also translate each title into ${langName(targetLang)} in "title_local".

PDF OUTLINE (bookmarks, may be empty):
$outline

FIRST PAGES (full text, usually contains the table of contents):
$frontText

FIRST LINES OF EVERY PAGE:
$pageHeads
''';

  static const structureSchema = {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
      'author': {'type': 'string'},
      'language': {'type': 'string'},
      'chapters': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'title_local': {'type': 'string'},
            'start_page': {'type': 'integer'},
            'include': {'type': 'boolean'},
          },
          'required': ['title', 'title_local', 'start_page', 'include'],
        },
      },
    },
    'required': ['title', 'language', 'chapters'],
  };

  // ---------------- Bob nomlarini tarjima ----------------
  static String translateTitlesPrompt(List<String> titles, String lang) => '''
Translate these book chapter titles into ${langName(lang)}. Keep numbering. Keep well-known technical terms understandable.
Return the same number of items in the same order.

${titles.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}
''';

  static const translateTitlesSchema = {
    'type': 'object',
    'properties': {
      'titles': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['titles'],
  };

  // ---------------- Dars (qism) ----------------
  static String teacherSystem(String lang) =>
      'You are a patient, brilliant teacher. You explain books to a learner in ${langName(lang)}. '
      'Your explanations are simple, clear and friendly, but you NEVER skip anything from the source: '
      'every idea, definition, argument, example, list item, table, formula and code fragment must be covered, '
      'in the same order as in the book. You simplify the language, not the content. '
      'All text you write must be in ${langName(lang)} '
      '(keep code, formulas and proper names as they are; for important technical terms give the original term in parentheses the first time).';

  static String lessonPrompt({
    required String bookTitle,
    required String chapterTitle,
    required int partNo,
    required int partCount,
    required String? previousTitle,
    required String source,
  }) =>
      '''
Book: "$bookTitle"
Chapter: "$chapterTitle"
Part $partNo of $partCount in this chapter.${previousTitle != null ? '\nPrevious part was about: "$previousTitle"' : ''}

Below is the ORIGINAL TEXT of this part (extracted from PDF, may contain page headers/footers and broken lines — ignore page headers, footers and page numbers).

Write a lesson that teaches this part:
- "title": a short, clear title for this part.
- "content": the full simplified explanation in Markdown. Use headings (##, ###), short paragraphs, bullet lists, **bold** for key ideas, tables if helpful, and fenced code blocks for code (translate only code comments). Go through the text in order and cover EVERYTHING — do not summarize away details, examples or numbers. Where something is hard, add a short everyday analogy or a tiny example (mark it with "💡"). If the text continues an idea from the previous part, connect it naturally.
- Figures/tables: when the text refers to a figure (e.g. "Figure 1-4"), keep the reference with its exact number, written in the lesson language (Uzbek: "1-4-rasm", Russian: "рис. 1-4", English: "Figure 1-4"). The app shows the picture right after that paragraph, so describe what it shows; never say the picture is missing.
- "key_points": 3-7 most important takeaways (one sentence each).
- "terms": important terms/notions introduced in this part with a one-sentence simple explanation (may be empty).

ORIGINAL TEXT:
"""
$source
"""
''';

  static const lessonSchema = {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
      'content': {'type': 'string'},
      'key_points': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'terms': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'term': {'type': 'string'},
            'explanation': {'type': 'string'},
          },
          'required': ['term', 'explanation'],
        },
      },
    },
    'required': ['title', 'content', 'key_points', 'terms'],
  };

  // ---------------- Bob yakuni ----------------
  static String _chapterHeader(String bookTitle, String chapterTitle, String material) => '''
Book: "$bookTitle"
Chapter: "$chapterTitle"

CHAPTER MATERIAL:
"""
$material
"""
''';

  static String qaPrompt(String book, String chapter, String material) => '''
${_chapterHeader(book, chapter, material)}
Create 8-12 review questions WITH answers that together cover the whole chapter (from basic understanding to deeper "why/how" questions).
Answers should be clear and simple, 2-6 sentences, Markdown allowed.
''';

  static const qaSchema = {
    'type': 'object',
    'properties': {
      'items': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'question': {'type': 'string'},
            'answer': {'type': 'string'},
          },
          'required': ['question', 'answer'],
        },
      },
    },
    'required': ['items'],
  };

  static String quizPrompt(String book, String chapter, String material) => '''
${_chapterHeader(book, chapter, material)}
Create a multiple-choice quiz of 10 questions covering the whole chapter.
Each question has exactly 4 options, exactly one correct ("correct_index" is 0-based).
Distractors must be plausible. Mix easy, medium and hard questions; include applied/scenario questions, not only definitions.
"explanation" explains why the correct answer is right (and why a typical wrong choice is wrong).
Randomize the position of the correct answer.
''';

  static const quizSchema = {
    'type': 'object',
    'properties': {
      'questions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'question': {'type': 'string'},
            'options': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'correct_index': {'type': 'integer'},
            'explanation': {'type': 'string'},
          },
          'required': ['question', 'options', 'correct_index', 'explanation'],
        },
      },
    },
    'required': ['questions'],
  };

  static String exercisesPrompt(String book, String chapter, String material) => '''
${_chapterHeader(book, chapter, material)}
Create 4-6 practical exercises that make the learner APPLY what this chapter teaches.
Order from easy to hard. If the book is technical (programming, math, science), include hands-on tasks (write code, solve a problem, calculate).
Otherwise use reflection, analysis, real-life application and mini-case tasks.
For each: "title", "task" (clear instructions, Markdown), "hint" (a gentle nudge, not the answer), "solution" (a model answer / solution in Markdown), "difficulty" (one of: easy, medium, hard).
''';

  static const exercisesSchema = {
    'type': 'object',
    'properties': {
      'exercises': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'task': {'type': 'string'},
            'hint': {'type': 'string'},
            'solution': {'type': 'string'},
            'difficulty': {'type': 'string'},
          },
          'required': ['title', 'task', 'hint', 'solution', 'difficulty'],
        },
      },
    },
    'required': ['exercises'],
  };

  static String checkExercisePrompt({
    required String chapter,
    required String task,
    required String solution,
    required String answer,
  }) =>
      '''
Chapter: "$chapter"

EXERCISE:
$task

MODEL SOLUTION (for your reference; the learner's answer may be different and still correct):
$solution

LEARNER'S ANSWER:
"""
$answer
"""

Evaluate the learner's answer kindly and honestly.
"score": 0-100.
"feedback": Markdown. Say what is correct, what is wrong or missing, and how to improve. If there are errors, show the corrected version. Be encouraging.
''';

  static const checkSchema = {
    'type': 'object',
    'properties': {
      'score': {'type': 'integer'},
      'feedback': {'type': 'string'},
    },
    'required': ['score', 'feedback'],
  };

  // ---------------- Savol berish (RAG) ----------------
  static String searchTermsPrompt({
    required String question,
    required String bookTitle,
    required String bookLang,
    required String learnerLang,
    required String? chapterTitle,
  }) =>
      """
A learner reading the book "$bookTitle"${chapterTitle != null ? ' (current chapter: "$chapterTitle")' : ''} asked (in ${langName(learnerLang)}):
"$question"

Produce 6-14 search terms for a keyword (BM25) index over the book text, which is written in language "$bookLang".
Include: the key concepts translated into the book's language (as the book would phrase them), important synonyms and technical terms, and the same key concepts in ${langName(learnerLang)}.
Use single words or very short phrases (1-3 words). No explanations.
""";

  static const searchTermsSchema = {
    'type': 'object',
    'properties': {
      'terms': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['terms'],
  };

  static String askRagPrompt({
    required String bookTitle,
    required String? chapterTitle,
    required List<String> sources,
    required List<({String role, String content})> history,
    required String question,
    required String lang,
  }) {
    final hist = history
        .map((m) => '${m.role == 'user' ? 'LEARNER' : 'TEACHER'}: ${m.content}')
        .join('\n\n');
    return """
The learner is studying the book "$bookTitle"${chapterTitle != null ? ', currently in chapter "$chapterTitle"' : ''}.

BOOK SOURCES (numbered excerpts found in the book; each has its chapter, part and pages):
${sources.isEmpty ? '(nothing relevant was found in the book)' : sources.join('\n\n---\n\n')}

${hist.isNotEmpty ? 'CONVERSATION SO FAR:\n$hist\n\n' : ''}LEARNER'S NEW QUESTION:
$question

How to answer:
- Answer in ${langName(lang)}, clearly and simply, in Markdown. Use small examples or analogies when they help.
- Base the answer on the BOOK SOURCES. After each fact taken from a source, cite it like [2] (several: [1][3]). Only cite sources that really support the sentence.
- When it helps the learner find it, say where in the book it is explained, in ${langName(lang)} (for example the chapter and part number).
- If the sources do not cover the question, say honestly that the book does not explain this (in the parts found), then still give a short helpful general answer and do not cite anything for it.
- Do not repeat the question. Do not list the sources at the end — the app shows them.
""";
  }
}
