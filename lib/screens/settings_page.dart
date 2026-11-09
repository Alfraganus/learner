import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/claude_service.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _path;
  late final TextEditingController _key;
  bool _showKey = false;
  bool _testing = false;
  bool _indexing = false;
  String? _test;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _path = TextEditingController(text: app.claudePath);
    _key = TextEditingController(text: app.claude.apiKey);
  }

  @override
  void dispose() {
    _path.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    final app = context.read<AppState>();
    if (app.mode == ClaudeMode.cli) {
      await app.setClaudePath(_path.text);
    } else {
      await app.setApiKey(_key.text);
    }
    setState(() {
      _testing = true;
      _test = null;
    });
    try {
      await app.claude.ping();
      _testOk = true;
      _test = app.mode == ClaudeMode.cli
          ? '${app.s.t('connection_ok_cli')}  ·  ${app.claude.executable}'
          : '${app.s.t('connection_ok_api')}  ·  ${ClaudeService.apiModelId(app.model)}';
    } catch (e) {
      _testOk = false;
      _test = '$e';
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _rebuildIndex() async {
    final app = context.read<AppState>();
    setState(() => _indexing = true);
    try {
      for (final b in app.allBooks.where((b) => b.status == BookStatus.ready)) {
        await app.rag.indexBookSource(b.id);
      }
      await app.rag.backfill();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(app.s.t('index_done'))));
      }
    } finally {
      if (mounted) setState(() => _indexing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final p = context.pal;

    Widget card(IconData icon, String title, String? sub, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 19, color: p.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: display(context, size: 17)),
                      if (sub != null) ...[
                        const SizedBox(height: 2),
                        Text(sub, style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
                      ],
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        );

    Widget option({
      required bool selected,
      required String title,
      required String sub,
      required VoidCallback onTap,
      IconData? icon,
    }) =>
        Expanded(
          child: Hoverable(
            onTap: onTap,
            radius: 16,
            color: selected ? p.accentSoft : p.surface,
            hoverColor: selected ? p.accentSoft : p.surfaceAlt,
            border: selected ? p.accent : p.border,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: selected ? p.accent : p.inkSoft),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(sub, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle_rounded, size: 18, color: p.accent),
              ],
            ),
          ),
        );

    final models = [
      ('sonnet', 'Sonnet', s.t('model_sonnet')),
      ('opus', 'Opus', s.t('model_opus')),
      ('haiku', 'Haiku', s.t('model_haiku')),
      ('fable', 'Fable', s.t('model_fable')),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(48, 44, 48, 48),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(s.t('preferences')),
              const SizedBox(height: 8),
              Text(s.t('settings'), style: serif(context, size: 42, weight: FontWeight.w700, height: 1.1)),
              const SizedBox(height: 32),

              // ---------------- Ulanish
              card(Icons.bolt_rounded, s.t('connection'), s.t('connection_sub'), [
                Row(children: [
                  option(
                    selected: app.mode == ClaudeMode.cli,
                    icon: Icons.terminal_rounded,
                    title: s.t('mode_cli'),
                    sub: s.t('mode_cli_sub'),
                    onTap: () => app.setMode(ClaudeMode.cli),
                  ),
                  const SizedBox(width: 12),
                  option(
                    selected: app.mode == ClaudeMode.api,
                    icon: Icons.key_rounded,
                    title: s.t('mode_api'),
                    sub: s.t('mode_api_sub'),
                    onTap: () => app.setMode(ClaudeMode.api),
                  ),
                ]),
                const SizedBox(height: 18),
                if (app.mode == ClaudeMode.cli)
                  TextField(
                    controller: _path,
                    decoration: InputDecoration(
                      labelText: s.t('claude_path'),
                      hintText: app.claude.executable,
                      prefixIcon: const Icon(Icons.folder_outlined),
                    ),
                    onSubmitted: app.setClaudePath,
                  )
                else ...[
                  TextField(
                    controller: _key,
                    obscureText: !_showKey,
                    decoration: InputDecoration(
                      labelText: s.t('api_key'),
                      hintText: 'sk-ant-…',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _showKey = !_showKey),
                      ),
                    ),
                    onSubmitted: app.setApiKey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    app.claude.hasEnvApiKey && app.claude.apiKey.isEmpty
                        ? s.t('api_key_env')
                        : s.t('api_key_hint'),
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  FilledButton.icon(
                    onPressed: _testing ? null : _runTest,
                    icon: _testing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: p.bg))
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: Text(app.mode == ClaudeMode.api ? s.t('save_and_test') : s.t('test_connection')),
                  ),
                ]),
                if (_test != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _testOk ? p.successSoft : p.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(_test!, style: TextStyle(fontSize: 13, color: p.ink)),
                  ),
                ],
              ]),

              // ---------------- Model
              card(Icons.psychology_alt_outlined, s.t('model'), s.t('model_sub'), [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final m in models)
                      SizedBox(
                        width: 352,
                        child: Row(children: [
                          option(
                            selected: app.model == m.$1,
                            title: m.$2,
                            sub: m.$3,
                            onTap: () => app.setModel(m.$1),
                          ),
                        ]),
                      ),
                  ],
                ),
              ]),

              // ---------------- Interfeys tili
              card(Icons.language_rounded, s.t('ui_language'), s.t('ui_language_hint'), [
                Row(children: [
                  for (final c in AppLang.codes) ...[
                    option(
                      selected: app.uiLang == c,
                      title: AppLang.label(c),
                      sub: AppLang.flag(c),
                      onTap: () => app.setUiLang(c),
                    ),
                    if (c != AppLang.codes.last) const SizedBox(width: 10),
                  ],
                ]),
              ]),

              // ---------------- O'rganish tili
              card(Icons.translate_rounded, s.t('language'), s.t('language_hint'), [
                Row(children: [
                  for (final c in AppLang.codes) ...[
                    option(
                      selected: app.lang == c,
                      title: AppLang.label(c),
                      sub: AppLang.native(c),
                      onTap: () => app.setLang(c),
                    ),
                    if (c != AppLang.codes.last) const SizedBox(width: 10),
                  ],
                ]),
              ]),

              // ---------------- Ko'rinish
              card(Icons.palette_outlined, s.t('theme'), null, [
                Row(children: [
                  option(
                    selected: app.themeMode == ThemeMode.system,
                    icon: Icons.brightness_auto_outlined,
                    title: s.t('theme_system'),
                    sub: s.t('theme_system_sub'),
                    onTap: () => app.setThemeMode(ThemeMode.system),
                  ),
                  const SizedBox(width: 10),
                  option(
                    selected: app.themeMode == ThemeMode.light,
                    icon: Icons.light_mode_outlined,
                    title: s.t('theme_light'),
                    sub: s.t('theme_light_sub'),
                    onTap: () => app.setThemeMode(ThemeMode.light),
                  ),
                  const SizedBox(width: 10),
                  option(
                    selected: app.themeMode == ThemeMode.dark,
                    icon: Icons.dark_mode_outlined,
                    title: s.t('theme_dark'),
                    sub: s.t('theme_dark_sub'),
                    onTap: () => app.setThemeMode(ThemeMode.dark),
                  ),
                ]),
              ]),

              // ---------------- Ma'lumotlar
              card(Icons.storage_rounded, s.t('data'), s.t('data_sub'), [
                SelectableText(app.repo.appDb.dataDir.path,
                    style: TextStyle(fontFamily: Fonts.mono, fontFamilyFallback: Fonts.monoFallback, fontSize: 12.5, color: p.inkSoft)),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _indexing ? null : _rebuildIndex,
                  icon: _indexing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.manage_search_rounded, size: 18),
                  label: Text(s.t('rebuild_index')),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
