import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/repo_store.dart';
import '../services/settings_store.dart';
import '../theme.dart';

class AiShortcut {
  AiShortcut(this.name, this.url, this.category, {this.package = ''});
  final String name;
  final String url;
  final String category; // texto, pesquisa, imagem, musica, video
  final String package;

  Map<String, String> toJson() =>
      {'n': name, 'u': url, 'c': category, 'p': package};
  static AiShortcut fromJson(Map m) =>
      AiShortcut('${m['n']}', '${m['u']}', '${m['c']}', package: '${m['p'] ?? ''}');
}

/// Lista inicial. Você edita no app (EDITAR): adicionar, remover.
/// Pacotes Android conhecidos abrem o app nativo; se não estiver instalado, abre o site aqui dentro.
List<AiShortcut> defaultShortcuts() => [
      AiShortcut('ChatGPT', 'https://chatgpt.com', 'texto', package: 'com.openai.chatgpt'),
      AiShortcut('Gemini', 'https://gemini.google.com', 'texto',
          package: 'com.google.android.apps.bard'),
      AiShortcut('Claude', 'https://claude.ai', 'texto', package: 'com.anthropic.claude'),
      AiShortcut('Grok', 'https://grok.com', 'texto', package: 'ai.x.grok'),
      AiShortcut('DeepSeek', 'https://chat.deepseek.com', 'texto', package: 'com.deepseek.chat'),
      AiShortcut('Copilot', 'https://copilot.microsoft.com', 'texto',
          package: 'com.microsoft.copilot'),
      AiShortcut('Le Chat', 'https://chat.mistral.ai', 'texto'),
      AiShortcut('Meta AI', 'https://www.meta.ai', 'texto'),
      AiShortcut('Perplexity', 'https://www.perplexity.ai', 'pesquisa',
          package: 'ai.perplexity.app.android'),
      AiShortcut('NotebookLM', 'https://notebooklm.google.com', 'pesquisa'),
      AiShortcut('Ideogram', 'https://ideogram.ai', 'imagem'),
      AiShortcut('Leonardo', 'https://app.leonardo.ai', 'imagem'),
      AiShortcut('Pollinations', 'https://pollinations.ai', 'imagem'),
      AiShortcut('Suno', 'https://suno.com', 'musica', package: 'com.suno.android'),
      AiShortcut('Udio', 'https://www.udio.com', 'musica'),
      AiShortcut('ElevenLabs', 'https://elevenlabs.io', 'musica'),
      AiShortcut('Kling', 'https://klingai.com', 'video'),
      AiShortcut('Runway', 'https://runwayml.com', 'video'),
      AiShortcut('Flow', 'https://labs.google/flow', 'video'),
      AiShortcut('Pika', 'https://pika.art', 'video'),
    ];

/// Q2: hub de atalhos para as melhores IAs, por categoria. Editável: toque em EDITAR para
/// adicionar, alterar ou remover atalhos.
class AiHubPanel extends StatefulWidget {
  const AiHubPanel({
    super.key,
    required this.settings,
    required this.repos,
    required this.runCommand,
    required this.noteSlugs,
  });
  final SettingsStore settings;
  final RepoStore repos;

  /// Executa um comando no console (ex.: "gh: commit dono/repo slug").
  final void Function(String cmd) runCommand;

  /// Lista os nomes (slugs) das notas do Vault para o botão ENVIAR NOTA.
  final Future<List<String>> Function() noteSlugs;

  @override
  State<AiHubPanel> createState() => AiHubPanelState();
}

class AiHubPanelState extends State<AiHubPanel> {
  static const _cats = [
    ('todas', 'TODAS'),
    ('texto', 'TEXTO'),
    ('pesquisa', 'PESQUISA'),
    ('imagem', 'IMAGEM'),
    ('musica', 'MÚSICA'),
    ('video', 'VÍDEO'),
    ('repos', 'REPOSITÓRIOS'),
  ];

  late List<AiShortcut> _items;
  String _cat = 'todas';
  bool _editing = false;
  String? _webTitle;
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();
    _items = _load();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(N.bg);
  }

  List<AiShortcut> _load() {
    final raw = widget.settings.hubJson;
    if (raw == null) return defaultShortcuts();
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          if ((e as Map)['c'] != 'google') AiShortcut.fromJson(e)
      ];
    } catch (_) {
      return defaultShortcuts();
    }
  }

  Future<void> _save() =>
      widget.settings.setHubJson(jsonEncode([for (final s in _items) s.toJson()]));

  /// Chamado pelo console: mostra a categoria pedida (ex.: 'video').
  void showCategory(String cat) => setState(() {
        _cat = _cats.any((c) => c.$1 == cat) ? cat : 'todas';
        _webTitle = null;
        _editing = false;
      });

  Future<void> _open(AiShortcut s) async {
    if (s.package.isNotEmpty) {
      try {
        final ok = await InstalledApps.startApp(s.package);
        if (ok == true) return;
      } catch (_) {}
    }
    setState(() => _webTitle = s.name);
    _web.loadRequest(Uri.parse(s.url));
  }

  /// Adiciona (existing == null) ou altera um atalho.
  Future<void> _edit([AiShortcut? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final url = TextEditingController(text: existing?.url ?? 'https://');
    final pkg = TextEditingController(text: existing?.package ?? '');
    var cat = existing?.category ?? (_cat == 'todas' || _cat == 'repos' ? 'texto' : _cat);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          title: Text(existing == null ? 'Novo atalho' : 'Editar atalho',
              style: N.t(c: N.cyan, w: FontWeight.w700)),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  style: N.t(),
                  decoration: InputDecoration(labelText: 'Nome', labelStyle: N.t(c: N.dim))),
              TextField(
                  controller: url,
                  style: N.t(),
                  decoration: InputDecoration(labelText: 'Endereço do site', labelStyle: N.t(c: N.dim))),
              TextField(
                  controller: pkg,
                  style: N.t(),
                  decoration: InputDecoration(
                      labelText: 'Pacote do app Android (opcional)', labelStyle: N.t(c: N.dim))),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: cat,
                isExpanded: true,
                dropdownColor: N.field,
                style: N.t(),
                items: [
                  for (final c in _cats.skip(1))
                    if (c.$1 != 'repos') DropdownMenuItem(value: c.$1, child: Text(c.$2)),
                ],
                onChanged: (v) => setD(() => cat = v ?? cat),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('CANCELAR', style: N.t(c: N.dim))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(existing == null ? 'ADICIONAR' : 'SALVAR',
                    style: N.t(c: N.cyan, w: FontWeight.w700))),
          ],
        );
      }),
    );
    if (ok != true || name.text.trim().isEmpty || !url.text.trim().startsWith('http')) return;
    final item = AiShortcut(name.text.trim(), url.text.trim(), cat, package: pkg.text.trim());
    setState(() {
      if (existing == null) {
        _items.add(item);
      } else {
        final i = _items.indexOf(existing);
        if (i >= 0) _items[i] = item;
      }
    });
    _save();
  }


  // ---------- Aba REPOSITÓRIOS ----------
  Future<void> _addRepo() async {
    final c = TextEditingController();
    List<String>? mine;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          title: Text('Adicionar repositório', style: N.t(c: N.cyan, w: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: c,
                autofocus: true,
                style: N.t(),
                decoration: InputDecoration(
                    labelText: 'dono/repo ou endereço do GitHub', labelStyle: N.t(c: N.dim)),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () async {
                    final l = await widget.repos.fetchMine();
                    setD(() => mine = l ?? []);
                  },
                  child: Text('BUSCAR NA MINHA CONTA (usa o token do CONFIG)',
                      style: N.t(c: N.cyan, s: 11, w: FontWeight.w700)),
                ),
              ),
              if (mine != null)
                SizedBox(
                  height: 160,
                  child: mine!.isEmpty
                      ? Center(child: Text('Nada encontrado. Confira o token.', style: N.t(c: N.dim)))
                      : ListView(children: [
                          for (final m in mine!)
                            ListTile(
                                dense: true,
                                title: Text(m, style: N.t()),
                                onTap: () => Navigator.pop(ctx, m)),
                        ]),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('CANCELAR', style: N.t(c: N.dim))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: Text('ADICIONAR', style: N.t(c: N.cyan, w: FontWeight.w700))),
          ],
        );
      }),
    );
    if (r == null || r.isEmpty) return;
    final ok = await widget.repos.add(r);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Use o formato dono/repo.')));
    }
    setState(() {});
  }

  Future<String?> _pickFrom(String title, List<String> options) => showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          title: Text(title, style: N.t(c: N.cyan, w: FontWeight.w700)),
          content: SizedBox(
            width: 380,
            height: 300,
            child: options.isEmpty
                ? Center(child: Text('Nada para escolher.', style: N.t(c: N.dim)))
                : ListView(children: [
                    for (final o in options)
                      ListTile(dense: true, title: Text(o, style: N.t()), onTap: () => Navigator.pop(ctx, o)),
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text('CANCELAR', style: N.t(c: N.dim))),
          ],
        ),
      );

  Future<void> _sendNote(String repo) async {
    final slug = await _pickFrom('Qual nota enviar para $repo?', await widget.noteSlugs());
    if (slug != null) widget.runCommand('gh: commit $repo $slug');
  }

  Future<void> _workflow(String repo) async {
    final c = TextEditingController();
    final ev = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text('Disparar workflow em $repo', style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: TextField(
            controller: c,
            autofocus: true,
            style: N.t(),
            decoration: InputDecoration(
                labelText: 'nome do evento (repository_dispatch)', labelStyle: N.t(c: N.dim))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('CANCELAR', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text('DISPARAR', style: N.t(c: N.cyan, w: FontWeight.w700))),
        ],
      ),
    );
    if (ev != null && ev.isNotEmpty) widget.runCommand('gh: dispatch $repo $ev');
  }

  Widget _smallBtn(String t, VoidCallback onTap, {bool accent = false}) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
              border: Border.all(color: accent ? N.cyan : N.border),
              borderRadius: BorderRadius.circular(4)),
          child: Text(t, style: N.t(c: accent ? N.cyan : N.dim, s: 11, w: FontWeight.w700)),
        ),
      );

  Widget _reposView() {
    final list = widget.repos.all;
    final def = widget.repos.defaultRepo;
    return Column(children: [
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Text('Nenhum repositório ainda. Toque em ADICIONAR REPOSITÓRIO.',
                    style: N.t(c: N.dim)))
            : ListView(padding: const EdgeInsets.all(10), children: [
                for (final r in list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        border: Border.all(color: N.border), borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      InkWell(
                        onTap: () async {
                          await widget.repos.setDefault(r);
                          if (mounted) setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(r == def ? '★' : '☆',
                              style: N.t(c: r == def ? N.amber : N.dim, s: 16)),
                        ),
                      ),
                      Expanded(
                          child: Text(r, style: N.t(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      _smallBtn('ABRIR', () {
                        setState(() => _webTitle = r);
                        _web.loadRequest(Uri.parse(widget.repos.url(r)));
                      }, accent: true),
                      _smallBtn('ENVIAR NOTA', () => _sendNote(r)),
                      _smallBtn('WORKFLOW', () => _workflow(r)),
                      if (_editing)
                        InkWell(
                          onTap: () async {
                            await widget.repos.remove(r);
                            if (mounted) setState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(color: N.red, shape: BoxShape.circle),
                            child: Text('x', style: N.t(c: N.bg, w: FontWeight.w700)),
                          ),
                        ),
                    ]),
                  ),
              ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Row(children: [
          InkWell(
            onTap: _addRepo,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: N.cyan), borderRadius: BorderRadius.circular(6)),
              child: Text('+ ADICIONAR REPOSITÓRIO',
                  style: N.t(c: N.cyan, s: 12, w: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text('★ = padrão do console (gh:). Enviar e disparar pedem sua confirmação.',
                  style: N.t(c: N.dim, s: 11), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    ]);
  }

  static const _tints = {
    'texto': Color(0xFF1B2A4A),
    'pesquisa': Color(0xFF143329),
    'imagem': Color(0xFF3B1D24),
    'musica': Color(0xFF2A1F44),
    'video': Color(0xFF3A3016),
  };
  static const _fg = {
    'texto': Color(0xFF93C5FD),
    'pesquisa': Color(0xFF86EFAC),
    'imagem': Color(0xFFFCA5A5),
    'musica': Color(0xFFC4B5FD),
    'video': Color(0xFFFCD34D),
  };

  Widget _tile(AiShortcut s) {
    final initials = s.name.length >= 2 ? s.name.substring(0, 2) : s.name;
    return InkWell(
      onTap: _editing ? () => _edit(s) : () => _open(s),
      child: SizedBox(
        width: 84,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 48,
                  width: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: _tints[s.category] ?? N.line2,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(initials,
                      style: N.t(c: _fg[s.category] ?? N.text, s: 17, w: FontWeight.w700)),
                ),
                const SizedBox(height: 4),
                Text(s.name,
                    style: N.t(c: N.dim, s: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
            if (_editing)
              Positioned(
                right: 8,
                top: -4,
                child: InkWell(
                  onTap: () {
                    setState(() => _items.remove(s));
                    _save();
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: N.red, shape: BoxShape.circle),
                    child: Text('x', style: N.t(c: N.bg, w: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? N.cyan : N.bg,
            border: Border.all(color: active ? N.cyan : N.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: N.t(c: active ? N.bg : N.dim, s: 11, w: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_webTitle != null) {
      return Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line2))),
            child: Row(children: [
              InkWell(
                onTap: () => setState(() => _webTitle = null),
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('< VOLTAR', style: N.t(c: N.cyan, w: FontWeight.w700))),
              ),
              Expanded(child: Text(_webTitle!, style: N.t(c: N.dim), overflow: TextOverflow.ellipsis)),
            ]),
          ),
          Expanded(child: WebViewWidget(controller: _web)),
        ],
      );
    }
    final shown = _items.where((s) => _cat == 'todas' || s.category == _cat).toList();
    final inRepos = _cat == 'repos';
    return Column(
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line2))),
          child: Row(children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final c in _cats) _chip(c.$2, _cat == c.$1, () => setState(() => _cat = c.$1)),
                ],
              ),
            ),
            _chip(_editing ? 'CONCLUIR' : 'EDITAR', _editing, () => setState(() => _editing = !_editing)),
          ]),
        ),
        if (_editing && !inRepos)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text('Toque num atalho para editar, no x para remover, ou em + nova IA.',
                style: N.t(c: N.dim, s: 11)),
          ),
        if (inRepos)
          Expanded(child: _reposView())
        else
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              children: [
                for (final s in shown) _tile(s),
                if (_editing)
                  InkWell(
                    onTap: () => _edit(),
                    child: Container(
                      width: 84,
                      height: 66,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          border: Border.all(color: N.cyan),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text('+ nova IA', style: N.t(c: N.cyan, w: FontWeight.w700, s: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
