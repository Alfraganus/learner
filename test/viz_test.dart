import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learner/state/app_state.dart';
import 'package:learner/ui/theme.dart';
import 'package:learner/widgets/viz_view.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

const _md = '''
Intro paragraph.

```viz
{"type":"steps","title":"Stack trace","steps":[
 {"note":"Start","array":[3,1,2],"vars":{"i":"0"},"stack":[]},
 {"note":"Push","array":[3,1,2],"highlight":[0],"pointers":{"i":0},"stack":["0"],"output":"x"}]}
```

```viz
{"type":"flow","title":"Request","direction":"down","nodes":[
 {"id":"a","label":"Browser","kind":"start"},{"id":"b","label":"Cached?","kind":"decision"},
 {"id":"c","label":"Server","kind":"box"},{"id":"d","label":"Database","kind":"data"},{"id":"e","label":"Response","kind":"end"}],
 "edges":[{"from":"a","to":"b"},{"from":"b","to":"e","label":"yes"},{"from":"b","to":"c","label":"no"},
 {"from":"c","to":"d"},{"from":"d","to":"c","label":"rows"},{"from":"c","to":"e"}]}
```

```viz
{"type":"flow","title":"Pipeline","direction":"right","nodes":[{"id":"a","label":"Lexer"},{"id":"b","label":"Parser"},{"id":"c","label":"Compiler"}],
 "edges":[{"from":"a","to":"b","label":"tokens"},{"from":"b","to":"c","label":"AST"}]}
```

```viz
{"type":"tree","title":"BST","root":{"label":"8","children":[{"label":"3","children":[{"label":"1"},{"label":"6","children":[{"label":"4"},{"label":"7"}]}]},{"label":"10","children":[{"label":"14"}]}]},"highlight":["6"]}
```

```viz
{"type":"bars","title":"n = 1000","unit":"ops","items":[{"label":"O(log n)","value":10},{"label":"O(n)","value":1000},{"label":"O(n log n)","value":10000}]}
```
''';

void main() {
  testWidgets('all viz types render without errors', (tester) async {
    final state = (await tester.runAsync(() async {
      final t = await Directory.systemTemp.createTemp('learner_viz');
      return AppState.create(dataDir: t.path, background: false);
    }))!;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 2600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(24), child: RichMd(_md))),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(VizView), findsNWidgets(5));
    expect(find.text('Cached?'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    // Keyingi qadam
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Push'), findsOneWidget);

    final out = Platform.environment['SHOTS_OUT'];
    if (out != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File(p.join(out, 'viz_all.png')).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });
}
