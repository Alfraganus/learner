import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learner/services/claude_service.dart';

/// Messages API'ni taqlid qiluvchi mahalliy SSE server.
Future<(HttpServer, List<Map<String, dynamic>>, List<HttpHeaders>)> _server(
    List<String> Function(Map<String, dynamic> body) events, {int status = 200}) async {
  final bodies = <Map<String, dynamic>>[];
  final headers = <HttpHeaders>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
    bodies.add(body);
    headers.add(req.headers);
    req.response.statusCode = status;
    if (status != 200) {
      req.response.write(jsonEncode({'type': 'error', 'error': {'type': 'authentication_error', 'message': 'bad key'}}));
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType('text', 'event-stream');
    for (final e in events(body)) {
      req.response.write('event: x\ndata: $e\n\n');
      await req.response.flush();
    }
    await req.response.close();
  });
  return (server, bodies, headers);
}

String _delta(String t) => jsonEncode({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': t}});
final _stop = jsonEncode({'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}});

void main() {
  test('API mode: structured output via output_config.format + SSE', () async {
    final (server, bodies, headers) = await _server((b) => [
          jsonEncode({'type': 'message_start', 'message': {'id': 'm1'}}),
          _delta('{"fruits": ["App'),
          _delta('le", "Banana"]}'),
          _stop,
          jsonEncode({'type': 'message_stop'}),
        ]);
    final c = ClaudeService(workDir: Directory.systemTemp.path)
      ..mode = ClaudeMode.api
      ..apiKey = 'sk-test'
      ..model = 'sonnet'
      ..apiUrl = 'http://127.0.0.1:${server.port}/v1/messages';
    final r = await c.structured(
      system: 'sys',
      prompt: 'Give 2 fruits',
      schema: {
        'type': 'object',
        'properties': {'fruits': {'type': 'array', 'items': {'type': 'string'}}},
      },
    );
    expect(r['fruits'], ['Apple', 'Banana']);
    final b = bodies.single;
    expect(b['model'], 'claude-sonnet-5-5');
    expect(b['stream'], true);
    expect(b['output_config']['format']['type'], 'json_schema');
    expect(b['output_config']['format']['schema']['additionalProperties'], false);
    expect(headers.single.value('x-api-key'), 'sk-test');
    expect(headers.single.value('anthropic-version'), isNotNull);
    await server.close(force: true);
  });

  test('API mode: text streaming calls onDelta, fast uses haiku', () async {
    final (server, bodies, _) = await _server((b) => [_delta('Salom'), _delta(', dunyo'), _stop]);
    final c = ClaudeService(workDir: Directory.systemTemp.path)
      ..mode = ClaudeMode.api
      ..apiKey = 'sk-test'
      ..apiUrl = 'http://127.0.0.1:${server.port}/v1/messages';
    final seen = <String>[];
    final t = await c.text(system: 's', prompt: 'p', fast: true, onDelta: seen.add);
    expect(t, 'Salom, dunyo');
    expect(seen, ['Salom', 'Salom, dunyo']);
    expect(bodies.single['model'], 'claude-haiku-5-5');
    expect(bodies.single.containsKey('fallbacks'), isFalse);
    await server.close(force: true);
  });

  test('API mode: 401 gives a clear error, missing key too', () async {
    final (server, _, _) = await _server((b) => [], status: 401);
    final c = ClaudeService(workDir: Directory.systemTemp.path)
      ..mode = ClaudeMode.api
      ..apiKey = 'bad'
      ..apiUrl = 'http://127.0.0.1:${server.port}/v1/messages';
    await expectLater(c.text(system: 's', prompt: 'p'),
        throwsA(isA<ClaudeException>().having((e) => e.message, 'msg', contains('401'))));
    c.apiKey = '';
    if ((Platform.environment['ANTHROPIC_API_KEY'] ?? '').isEmpty) {
      await expectLater(c.text(system: 's', prompt: 'p'), throwsA(isA<ClaudeException>()));
    }
    await server.close(force: true);
  });
}
