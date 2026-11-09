import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../l10n/strings.dart';

class ClaudeException implements Exception {
  ClaudeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Claude'ga ulanish usuli.
enum ClaudeMode {
  /// `claude -p` (Claude Code CLI, obuna yoki CLI'dagi login).
  cli,

  /// Anthropic Messages API (API kalit bilan, to'g'ridan-to'g'ri HTTP).
  api,
}

/// Bir vaqtda ishlaydigan so'rovlar sonini cheklaydi.
/// Foydalanuvchi kutayotgan so'rovlar oldindan tayyorlash so'rovlaridan oldin bajariladi.
class _Semaphore {
  _Semaphore(this.max);
  int max;
  int _active = 0;
  final _high = Queue<Completer<void>>();
  final _low = Queue<Completer<void>>();

  Future<void> acquire({bool background = false}) {
    if (_active < max) {
      _active++;
      return Future.value();
    }
    final c = Completer<void>();
    (background ? _low : _high).add(c);
    return c.future;
  }

  void release() {
    if (_high.isNotEmpty) {
      _high.removeFirst().complete();
    } else if (_low.isNotEmpty) {
      _low.removeFirst().complete();
    } else {
      _active--;
    }
  }
}

/// Claude bilan barcha muloqot: ikki rejim — `claude -p` CLI yoki Anthropic API kaliti.
/// Qolgan kod qaysi rejim ishlayotganini bilmaydi: faqat [structured] va [text] chaqiriladi.
class ClaudeService {
  ClaudeService({required this.workDir});

  final String workDir;
  ClaudeMode mode = ClaudeMode.cli;

  /// Model taxallusi: sonnet | opus | haiku | fable (yoki to'liq model ID).
  String model = 'sonnet';
  String executableOverride = '';
  String apiKey = '';
  Duration timeout = const Duration(minutes: 20);

  /// Diagnostika uchun (ixtiyoriy).
  void Function(String msg)? log;

  final _sem = _Semaphore(2);
  final _running = <Process>{};
  final _http = http.Client();
  String? _resolved;

  /// Messages API manzili (testlarda mahalliy serverga almashtiriladi).
  String apiUrl = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2026-10-21';

  /// Taxallusdan API model ID.
  static String apiModelId(String alias) => switch (alias.trim()) {
        'opus' => 'claude-opus-5-5',
        'sonnet' => 'claude-sonnet-5-5',
        'haiku' => 'claude-haiku-5-5',
        'fable' => 'claude-fable-5-1',
        final other => other,
      };

  String get effectiveApiKey {
    if (apiKey.trim().isNotEmpty) return apiKey.trim();
    return Platform.environment['ANTHROPIC_API_KEY']?.trim() ?? '';
  }

  bool get hasEnvApiKey => (Platform.environment['ANTHROPIC_API_KEY'] ?? '').trim().isNotEmpty;

  // ---------------------------------------------------------------- CLI yo'li
  String get executable {
    if (executableOverride.trim().isNotEmpty) return executableOverride.trim();
    return _resolved ??= _resolveExecutable();
  }

  static String _resolveExecutable() {
    final isWin = Platform.isWindows;
    final names = isWin ? ['claude.exe', 'claude'] : ['claude'];
    final pathVar = Platform.environment['PATH'] ?? '';
    final dirs = pathVar.split(isWin ? ';' : ':').where((d) => d.isNotEmpty).toList();
    final home = Platform.environment[isWin ? 'USERPROFILE' : 'HOME'];
    if (home != null) {
      dirs.add(p.join(home, '.local', 'bin'));
      dirs.add(p.join(home, '.claude', 'local'));
    }
    if (!isWin) dirs.addAll(['/usr/local/bin', '/opt/homebrew/bin']);
    for (final d in dirs) {
      for (final n in names) {
        final f = File(p.join(d, n));
        if (f.existsSync()) return f.path;
      }
    }
    return 'claude';
  }

  void resetResolution() => _resolved = null;

  void killAll() {
    for (final pr in _running.toList()) {
      pr.kill();
    }
  }

  // ---------------------------------------------------------------- Umumiy API
  /// JSON sxema bo'yicha tuzilgan javob.
  /// [fast] — yordamchi ishlar uchun tez va arzon model (haiku).
  Future<Map<String, dynamic>> structured({
    required String system,
    required String prompt,
    required Map<String, dynamic> schema,
    bool background = false,
    bool fast = false,
  }) async {
    await _sem.acquire(background: background);
    try {
      if (mode == ClaudeMode.api) {
        final txt = await _apiCall(system, prompt,
            schema: schema, fast: fast, maxTokens: fast ? 4000 : 32000);
        final parsed = _extractJson(txt);
        if (parsed == null) throw ClaudeException(S.ui.t('err_no_structured'));
        return parsed;
      }
      final out = await _cliCall(system, prompt, schema: schema, fast: fast);
      final so = out['structured_output'];
      if (so is Map) return Map<String, dynamic>.from(so);
      final parsed = _extractJson('${out['result'] ?? ''}');
      if (parsed != null) return parsed;
      throw ClaudeException(S.ui.t('err_no_structured'));
    } finally {
      _sem.release();
    }
  }

  /// Oddiy matnli javob. API rejimida [onDelta] har yangi matn bo'lagida chaqiriladi.
  Future<String> text({
    required String system,
    required String prompt,
    bool background = false,
    bool fast = false,
    void Function(String textSoFar)? onDelta,
  }) async {
    await _sem.acquire(background: background);
    try {
      if (mode == ClaudeMode.api) {
        return (await _apiCall(system, prompt, fast: fast, maxTokens: 16000, onDelta: onDelta))
            .trim();
      }
      final out = await _cliCall(system, prompt, fast: fast);
      final r = '${out['result'] ?? ''}'.trim();
      onDelta?.call(r);
      return r;
    } finally {
      _sem.release();
    }
  }

  /// Ulanishni tekshirish.
  Future<String> ping() => text(system: 'Reply with exactly: OK', prompt: 'ping', fast: true);

  // ---------------------------------------------------------------- CLI
  Future<Map<String, dynamic>> _cliCall(String system, String prompt,
      {Map<String, dynamic>? schema, bool fast = false}) async {
    await Directory(workDir).create(recursive: true);
    final m = fast ? 'haiku' : model.trim();
    final args = <String>[
      '-p',
      '--output-format', 'json',
      '--tools', '',
      '--no-session-persistence',
      '--strict-mcp-config',
      '--disable-slash-commands',
      '--system-prompt', system,
      if (m.isNotEmpty) ...['--model', m],
      if (schema != null) ...['--json-schema', jsonEncode(schema)],
    ];

    final Process proc;
    try {
      proc = await Process.start(executable, args, workingDirectory: workDir, runInShell: false);
    } on ProcessException catch (e) {
      throw ClaudeException('${S.ui.t('err_cli_missing', {'exe': executable})}\n${e.message}');
    }
    _running.add(proc);
    final sw = Stopwatch()..start();
    log?.call('cli start pid=${proc.pid} schema=${schema != null} prompt=${prompt.length}');

    // Natijani bo'laklab yig'amiz: jarayon tugagach pipe'ni boshqa (nabira) jarayon
    // ushlab qolsa ham, yig'ilgan ma'lumot bilan davom eta olamiz.
    final outBuf = StringBuffer();
    final errBuf = StringBuffer();
    final outDone = proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(outBuf.write)
        .asFuture<void>();
    final errDone = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(errBuf.write)
        .asFuture<void>();
    proc.stdin.add(utf8.encode(prompt));
    await proc.stdin.flush();
    await proc.stdin.close();

    int code;
    try {
      code = await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      proc.kill();
      throw ClaudeException(S.ui.t('err_timeout'));
    } finally {
      _running.remove(proc);
    }
    await outDone.timeout(const Duration(seconds: 5), onTimeout: () {});
    await errDone.timeout(const Duration(seconds: 2), onTimeout: () {});
    final stdout = outBuf.toString();
    final stderr = errBuf.toString();
    log?.call('cli exit pid=${proc.pid} code=$code ${sw.elapsed.inSeconds}s out=${stdout.length}');

    final json = _parseCliOutput(stdout);
    if (json == null) {
      final msg = [stderr.trim(), stdout.trim()].where((s) => s.isNotEmpty).join('\n');
      throw ClaudeException(S.ui.t('err_cli_code',
          {'code': code, 'msg': msg.isEmpty ? S.ui.t('err_no_answer') : _short(msg)}));
    }
    if (json['is_error'] == true) {
      throw ClaudeException(S.ui.t('err_claude', {'msg': _short('${json['result'] ?? json['subtype']}')}));
    }
    return json;
  }

  static Map<String, dynamic>? _parseCliOutput(String stdout) {
    final s = stdout.trim();
    if (s.isEmpty) return null;
    try {
      final v = jsonDecode(s);
      if (v is Map) return Map<String, dynamic>.from(v);
      if (v is List) {
        for (final e in v.reversed) {
          if (e is Map && e['type'] == 'result') return Map<String, dynamic>.from(e);
        }
      }
    } catch (_) {}
    for (final line in s.split('\n').reversed) {
      try {
        final v = jsonDecode(line.trim());
        if (v is Map && v['type'] == 'result') return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return null;
  }

  // ---------------------------------------------------------------- API
  /// Messages API'ga oqimli (SSE) so'rov. Uzun javoblarda HTTP timeout bo'lmasligi uchun
  /// har doim stream ishlatiladi. Matn bloklari yig'ilib qaytariladi.
  Future<String> _apiCall(
    String system,
    String prompt, {
    Map<String, dynamic>? schema,
    bool fast = false,
    int maxTokens = 16000,
    void Function(String)? onDelta,
  }) async {
    final key = effectiveApiKey;
    if (key.isEmpty) {
      throw ClaudeException(S.ui.t('err_no_key'));
    }
    final modelId = apiModelId(fast ? 'haiku' : model);
    final useFallback = !modelId.startsWith('claude-haiku');
    final body = <String, dynamic>{
      'model': modelId,
      'max_tokens': maxTokens,
      'stream': true,
      'system': system,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'output_config': {
        'effort': fast ? 'low' : 'medium',
        if (schema != null) 'format': {'type': 'json_schema', 'schema': strictSchema(schema)},
      },
      if (useFallback) 'fallbacks': 'default',
    };
    final headers = {
      'content-type': 'application/json',
      'x-api-key': key,
      'anthropic-version': _apiVersion,
      if (useFallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
    };

    var attempt = 0;
    while (true) {
      attempt++;
      final sw = Stopwatch()..start();
      log?.call('api start model=$modelId schema=${schema != null} prompt=${prompt.length}');
      final req = http.Request('POST', Uri.parse(apiUrl))
        ..headers.addAll(headers)
        ..body = jsonEncode(body);
      http.StreamedResponse res;
      try {
        res = await _http.send(req).timeout(const Duration(minutes: 2));
      } on TimeoutException {
        if (attempt < 3) continue;
        throw ClaudeException(S.ui.t('err_api_timeout'));
      } on SocketException catch (e) {
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        throw ClaudeException(S.ui.t('err_network', {'msg': e.message}));
      }

      if (res.statusCode != 200) {
        final errText = await res.stream.bytesToString();
        final retryable = res.statusCode == 429 || res.statusCode >= 500;
        if (retryable && attempt < 4) {
          final ra = int.tryParse(res.headers['retry-after'] ?? '');
          await Future.delayed(Duration(seconds: ra ?? (3 * attempt)));
          continue;
        }
        throw ClaudeException(_apiErrorMessage(res.statusCode, errText));
      }

      final text = StringBuffer();
      String? stopReason;
      String? errorMsg;
      final lines = res.stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .timeout(timeout);
      try {
        await for (final line in lines) {
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data.isEmpty) continue;
          Map<String, dynamic> ev;
          try {
            ev = Map<String, dynamic>.from(jsonDecode(data) as Map);
          } catch (_) {
            continue;
          }
          switch (ev['type']) {
            case 'content_block_delta':
              final d = ev['delta'];
              if (d is Map && d['type'] == 'text_delta') {
                text.write(d['text'] ?? '');
                onDelta?.call(text.toString());
              }
            case 'message_delta':
              final d = ev['delta'];
              if (d is Map && d['stop_reason'] != null) stopReason = '${d['stop_reason']}';
            case 'error':
              final e = ev['error'];
              errorMsg = e is Map ? '${e['type']}: ${e['message']}' : '$e';
          }
        }
      } on TimeoutException {
        throw ClaudeException(S.ui.t('err_timeout'));
      }
      log?.call('api done ${sw.elapsed.inSeconds}s stop=$stopReason chars=${text.length}');

      if (errorMsg != null) {
        if (errorMsg.contains('overloaded') && attempt < 4) {
          await Future.delayed(Duration(seconds: 3 * attempt));
          continue;
        }
        throw ClaudeException(S.ui.t('err_claude', {'msg': errorMsg}));
      }
      if (stopReason == 'refusal') {
        throw ClaudeException(S.ui.t('err_refused'));
      }
      if (stopReason == 'max_tokens' && schema != null) {
        throw ClaudeException(S.ui.t('err_truncated'));
      }
      return text.toString();
    }
  }

  static String _apiErrorMessage(int status, String body) {
    String detail = body;
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) detail = '${j['error']['message']}';
    } catch (_) {}
    return switch (status) {
      401 => S.ui.t('err_401'),
      403 => S.ui.t('err_403', {'msg': _short(detail)}),
      404 => S.ui.t('err_404', {'msg': _short(detail)}),
      429 => S.ui.t('err_429'),
      _ => S.ui.t('err_api', {'code': status, 'msg': _short(detail)}),
    };
  }

  /// Structured outputs talabi: har bir obyektda `additionalProperties: false`
  /// va barcha xossalar `required`.
  static Map<String, dynamic> strictSchema(Map<String, dynamic> schema) {
    dynamic walk(dynamic node) {
      if (node is Map) {
        final m = <String, dynamic>{};
        node.forEach((k, v) => m['$k'] = walk(v));
        if (m['type'] == 'object' && m['properties'] is Map) {
          m['additionalProperties'] = false;
          m['required'] = (m['properties'] as Map).keys.toList();
        }
        return m;
      }
      if (node is List) return node.map(walk).toList();
      return node;
    }

    return Map<String, dynamic>.from(walk(schema) as Map);
  }

  static Map<String, dynamic>? _extractJson(String s) {
    try {
      final v = jsonDecode(s.trim());
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final v = jsonDecode(s.substring(start, end + 1));
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  static String _short(String s) => s.length > 600 ? '${s.substring(0, 600)}…' : s;
}
