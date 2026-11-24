import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:learner/services/interview_service.dart';
import 'package:learner/services/video_tools.dart';
import 'package:learner/services/web_source.dart';
import 'package:learner/widgets/viz_view.dart';

void main() {
  test('splitViz separates viz blocks, keeps other code and broken JSON', () {
    const md = '''
Intro text.

```viz
{"type":"steps","title":"Bubble","steps":[{"note":"start","array":[3,1]}]}
```

Middle.

```php
<?php echo "```viz inside code is not a block"; ?>
```

```viz
{"type": "bars", broken
```
End.''';
    final parts = splitViz(md);
    expect(parts.where((p) => p.viz != null).length, 1);
    expect(parts[1].viz!['type'], 'steps');
    expect(parts.first.text, contains('Intro text.'));
    final rest = parts.last.text;
    expect(rest, contains('```php'));
    expect(rest, contains('```json')); // buzilgan JSON kod sifatida ko'rinadi
    expect(rest, contains('End.'));
  });

  test('YouTube links are normalized', () {
    const id = 'c6zu897JVQY';
    for (final u in [
      'https://www.youtube.com/watch?v=$id&t=30s',
      'youtube.com/watch?v=$id',
      'https://youtu.be/$id?si=abc',
      'https://m.youtube.com/watch?v=$id',
      'https://www.youtube.com/shorts/$id',
      'https://www.youtube.com/live/$id',
    ]) {
      expect(InterviewService.normalizeUrl(u), 'https://www.youtube.com/watch?v=$id', reason: u);
    }
    expect(InterviewService.normalizeUrl('https://example.com/watch?v=$id'), isNull);
    expect(InterviewService.normalizeUrl('https://www.youtube.com/@channel'), isNull);
  });

  test('json3 subtitles become readable timed lines without glued words', () {
    const json = '''
{"events":[
 {"tStartMs":400,"dDurationMs":4000,"segs":[{"utf8":"\$194,000"},{"utf8":" is","tOffsetMs":500},{"utf8":" how","tOffsetMs":900}]},
 {"tStartMs":4400,"aAppend":1,"segs":[{"utf8":"\\n"}]},
 {"tStartMs":5000,"segs":[{"utf8":"much"},{"utf8":" Google","tOffsetMs":300},{"utf8":" pays.","tOffsetMs":600}]},
 {"tStartMs":30000,"segs":[{"utf8":"Next"},{"utf8":" sentence","tOffsetMs":200}]}
]}''';
    final cues = VideoTools.parseJson3(json);
    expect(cues.first.start, closeTo(0.4, 0.01));
    expect(cues.map((c) => c.text).join(' '), contains(r'$194,000 is how much Google pays.'));
    expect(cues.last.text, 'Next sentence');
  });

  test('subtitle choice prefers manual subs in the video language, then original auto captions', () {
    VideoInfo info(Map<String, dynamic> subs, Map<String, dynamic> auto, String? lang) =>
        VideoInfo({'subtitles': subs, 'automatic_captions': auto, 'language': lang});
    expect(info({'en': [], 'live_chat': []}, {'en-orig': []}, 'en').pickSubtitles(), (key: 'en', auto: false));
    expect(info({}, {'ru-orig': [], 'ru': [], 'en': []}, 'ru-RU').pickSubtitles(), (key: 'ru-orig', auto: true));
    expect(info({}, {'de': [], 'en-orig': []}, null).pickSubtitles(), (key: 'en-orig', auto: true));
    expect(info({}, {}, 'en').pickSubtitles(), isNull);
  });

  test('web page is turned into markdown: menu, ads and buttons dropped, code kept', () {
    final doc = html.parse('''
<html><head><title>PHP Variables - W3</title></head><body>
<div id="leftmenuinnerinner">
  <a href="default.asp">Home</a><a href="php_intro.asp">Intro</a><a href="php_syntax.asp">Syntax</a>
  <a href="php_variables.asp">Variables</a><a href="func_array.asp">array()</a><a href="php_quiz.asp">Quiz</a>
  <a href="/css/default.asp">CSS</a>
</div>
<div id="main">
  <h1>PHP <span>Variables</span></h1>
  <div id="mainLeaderboard">AD here</div>
  <p>Variables are <b>containers</b> for storing data.</p>
  <div class="w3-example"><h3>Example</h3>
    <div class="w3-code notranslate">&lt;?php<br>&nbsp;&nbsp;\$x = 5;<br>echo \$x;<br>?&gt;</div>
    <a class="w3-btn" href="tryit.asp">Try it Yourself »</a>
  </div>
  <ul><li>Starts with <code>\$</code></li><li>Case-sensitive</li></ul>
  <table><tr><th>Name</th><th>Value</th></tr><tr><td>x</td><td>5</td></tr></table>
  <div class="nextprev"><a href="php_syntax.asp">❮ Previous</a></div>
</div></body></html>''');
    final base = Uri.parse('https://www.w3schools.com/php/php_variables.asp');
    final page = WebSource.extract(doc, base);
    expect(page.title, 'PHP Variables');
    expect(page.text, contains('Variables are **containers** for storing data.'));
    expect(page.text, contains('```\n<?php\n  \$x = 5;\necho \$x;\n?>\n```'));
    expect(page.text, contains('- Starts with `\$`'));
    expect(page.text, contains('| Name | Value |'));
    expect(page.text, isNot(contains('AD here')));
    expect(page.text, isNot(contains('Try it Yourself')));
    expect(page.text, isNot(contains('Previous')));

    final links = WebSource.sectionLinks(html.parse(doc.outerHtml), base);
    expect(links, [
      'https://www.w3schools.com/php/php_variables.asp',
      'https://www.w3schools.com/php/default.asp',
      'https://www.w3schools.com/php/php_intro.asp',
      'https://www.w3schools.com/php/php_syntax.asp',
    ]);
  });
}
