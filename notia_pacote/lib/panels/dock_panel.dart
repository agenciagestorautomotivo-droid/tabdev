import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/dock_model.dart';
import '../services/media_service.dart';
import '../theme.dart';

/// Q4: dock com até 5 pastas editáveis + navegador agentic.
/// Os dados das pastas vêm do [DockModel], compartilhado com o painel Q5 (Apps instalados).
class DockPanel extends StatefulWidget {
  const DockPanel({
    super.key,
    required this.model,
    required this.media,
    required this.onPageText,
  });
  final DockModel model;
  final MediaService media;
  final void Function(String text, String url) onPageText;

  @override
  State<DockPanel> createState() => DockPanelState();
}

class DockPanelState extends State<DockPanel> {
  bool _browser = false;
  bool _editing = false;
  DockModel get _m => widget.model;

  late final WebViewController _web;
  final _url = TextEditingController(text: 'https://duckduckgo.com');
  static const _hideMedia =
      "(function(){var s=document.createElement('style');"
      "s.textContent='img,picture,video,canvas,iframe{display:none!important}';"
      "(document.head||document.documentElement).appendChild(s);})();";

  static const _extract =
      "(function(){var c=document.body.cloneNode(true);"
      "c.querySelectorAll('script,style,nav,footer,iframe,aside,noscript').forEach(function(e){e.remove()});"
      "return (c.innerText||c.textContent||'').replace(/\\s+/g,' ').trim();})()";

  @override
  void initState() {
    super.initState();
    _m.addListener(_onModel);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(N.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          final u = r.url.toLowerCase();
          final blocked = ['.apk', '.exe', '.msi'].any(u.endsWith);
          return blocked ? NavigationDecision.prevent : NavigationDecision.navigate;
        },
        onPageStarted: (u) => _web.runJavaScript(_hideMedia),
        onPageFinished: (u) {
          _web.runJavaScript(_hideMedia);
          if (mounted) _url.text = u;
        },
      ));
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _m.removeListener(_onModel);
    _url.dispose();
    super.dispose();
  }

  // ---------- API externa ----------
  Future<void> refresh() => _m.refresh();

  AppInfo? _byPkg(String p) => _m.byPkg(p);

  // ---------- API externa ----------
  static String _norm(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    var r = s.toLowerCase().trim();
    for (var i = 0; i < from.length; i++) {
      r = r.replaceAll(from[i], to[i]);
    }
    return r;
  }

  /// Abre um app pelo nome (voz ou texto). Retorna o nome do app aberto, ou null.
  Future<String?> launchByName(String query) async {
    final q = _norm(query);
    if (q.isEmpty) return null;
    AppInfo? best;
    var bestScore = 0;
    for (final a in _m.all) {
      final n = _norm(a.name);
      final score = n == q ? 3 : n.startsWith(q) ? 2 : n.contains(q) ? 1 : 0;
      if (score > bestScore) {
        best = a;
        bestScore = score;
      }
    }
    if (best == null) return null;
    await InstalledApps.startApp(best.packageName);
    return best.name;
  }

  /// Abre a Play Store: na busca por [query] ou, sem texto, na tela inicial dela.
  Future<void> openStore([String? query]) async {
    if (query == null || query.trim().isEmpty) {
      final ok = await InstalledApps.startApp('com.android.vending');
      if (ok == true) return;
    }
    final q = Uri.encodeQueryComponent(query ?? '');
    for (final u in ['market://search?q=$q&c=apps', 'https://play.google.com/store/search?q=$q&c=apps']) {
      try {
        if (await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
  }
  void openUrl(String url) {
    setState(() => _browser = true);
    _go(url);
  }

  void _go(String input) {
    var u = input.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http')) {
      u = u.contains('.') && !u.contains(' ')
          ? 'https://$u'
          : 'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(u)}';
    }
    _url.text = u;
    _web.loadRequest(Uri.parse(u));
  }

  Future<void> _readPage() async {
    try {
      final r = await _web.runJavaScriptReturningResult(_extract);
      var s = r.toString();
      if (s.startsWith('"')) s = jsonDecode(s) as String;
      if (s.length > 3000) s = s.substring(0, 3000);
      widget.onPageText(s, await _web.currentUrl() ?? '');
    } catch (_) {
      widget.onPageText('', '');
    }
  }

  // ---------- Edição ----------
  Future<String?> _ask(String title, String hint, {String initial = ''}) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text(title, style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: TextField(
            controller: c,
            autofocus: true,
            style: N.t(),
            decoration: InputDecoration(hintText: hint, hintStyle: N.t(c: N.dim))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CANCELAR', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text('OK', style: N.t(c: N.cyan, w: FontWeight.w700))),
        ],
      ),
    );
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _newFolder() async {
    final n = await _ask('Nova pasta', 'Nome da pasta');
    if (n != null) await _m.addFolder(n);
  }

  /// Escolhe um app que ainda não está nesta pasta (os sem pasta aparecem primeiro).
  Future<void> _addApp(int folder) async {
    final search = TextEditingController();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final q = search.text.toLowerCase();
        final inThis = (_m.folders[folder]['i'] as List).cast<String>();
        final list = _m.all
            .where((a) => !inThis.contains(a.packageName) && a.name.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) {
            final fa = _m.folderIndexOf(a.packageName) < 0 ? 0 : 1;
            final fb = _m.folderIndexOf(b.packageName) < 0 ? 0 : 1;
            return fa != fb ? fa - fb : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        return Dialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 420,
            height: 480,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: search,
                  style: N.t(),
                  onChanged: (_) => setD(() {}),
                  decoration: InputDecoration(
                      hintText: 'Buscar app', hintStyle: N.t(c: N.dim), isDense: true),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (c, i) => ListTile(
                    dense: true,
                    leading: _icon(list[i], 28),
                    title: Text(list[i].name, style: N.t()),
                    subtitle: _m.folderNameOf(list[i].packageName) == null
                        ? null
                        : Text('em ${_m.folderNameOf(list[i].packageName)}',
                            style: N.t(c: N.dim, s: 10)),
                    onTap: () => Navigator.pop(c, list[i].packageName),
                  ),
                ),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('FECHAR', style: N.t(c: N.dim))),
            ]),
          ),
        );
      }),
    );
    if (picked != null) await _m.moveToFolder([picked], folder);
  }

  // ---------- Widgets ----------
  Widget _icon(AppInfo a, double size) {
    final Uint8List? bytes = a.icon;
    if (bytes == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: N.line2, borderRadius: BorderRadius.circular(size / 4)),
        child: Text(a.name.isEmpty ? '?' : a.name[0].toUpperCase(),
            style: N.t(w: FontWeight.w700)),
      );
    }
    return Image.memory(bytes, width: size, height: size, gaplessPlayback: true);
  }

  Widget _label(String t) => Text(t,
      style: N.t(c: N.dim, s: 11),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center);

  Widget _appBody(AppInfo a) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [_icon(a, 48), const SizedBox(height: 4), _label(a.name)],
      );

  Widget _folderBody(Map<String, dynamic> f) {
    final pk = (f['i'] as List).cast<String>();
    final minis = [for (final p in pk.take(4)) _byPkg(p)].whereType<AppInfo>().toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: N.line2,
              border: Border.all(color: N.border),
              borderRadius: BorderRadius.circular(12)),
          child: Wrap(spacing: 2, runSpacing: 2, children: [
            for (final a in minis) _icon(a, 18),
          ]),
        ),
        const SizedBox(height: 4),
        _label('${f['n']}'),
      ],
    );
  }

  Widget _badge(VoidCallback onTap) => Positioned(
        right: 4,
        top: -4,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: N.red, shape: BoxShape.circle),
            child: Text('x', style: N.t(c: N.bg, w: FontWeight.w700, s: 13)),
          ),
        ),
      );

  Widget _rootTile(int i) {
    final it = _m.folders[i];
    final tile = SizedBox(
      width: 96,
      child: Stack(clipBehavior: Clip.none, children: [
        _folderBody(it),
        if (_editing) _badge(() => _confirmRemoveFolder(i)),
      ]),
    );
    if (!_editing) return InkWell(onTap: () => _openFolder(i), child: tile);
    return DragTarget<int>(
      onAcceptWithDetails: (d) => _m.reorderFolder(d.data, i),
      builder: (c, cand, rej) => Draggable<int>(
        data: i,
        feedback: Material(color: Colors.transparent, child: tile),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: InkWell(onTap: () => _openFolder(i), child: tile),
      ),
    );
  }

  Future<void> _confirmRemoveFolder(int i) async {
    final n = '${_m.folders[i]['n']}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text('Remover a pasta "$n"?', style: N.t(c: N.red, w: FontWeight.w700)),
        content: Text('Os apps dela ficam "sem pasta" no painel de Apps instalados. Nada é desinstalado.',
            style: N.t(c: N.dim)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('CANCELAR', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('REMOVER', style: N.t(c: N.red, w: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true) await _m.removeFolder(i);
  }

  Future<void> _openFolder(int idx) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(listenable: _m, builder: (ctx, _) {
        if (idx >= _m.folders.length) return const SizedBox.shrink();
        final f = _m.folders[idx];
        final pk = (f['i'] as List).cast<String>();
        final isMedia = ['mídia', 'midia'].contains('${f['n']}'.toLowerCase());
        return Dialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 460,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                      child: Text('${f['n']}', style: N.t(c: N.cyan, w: FontWeight.w700, s: 15))),
                  if (_editing) ...[
                    TextButton(
                      onPressed: () async {
                        final n = await _ask('Renomear pasta', 'Nome', initial: '${f['n']}');
                        if (n != null) await _m.renameFolder(idx, n);
                      },
                      child: Text('RENOMEAR', style: N.t(c: N.dim, s: 12)),
                    ),
                    TextButton(
                      onPressed: () => _addApp(idx),
                      child: Text('+ APP', style: N.t(c: N.cyan, s: 12, w: FontWeight.w700)),
                    ),
                  ],
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('FECHAR', style: N.t(c: N.dim, s: 12))),
                ]),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(spacing: 12, runSpacing: 14, children: [
                      if (isMedia)
                        InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            _openLibrary();
                          },
                          child: SizedBox(
                            width: 84,
                            child: Column(children: [
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: const Color(0xFF1B3A3A),
                                    borderRadius: BorderRadius.circular(12)),
                                child: Text('IA', style: N.t(c: N.cyan, w: FontWeight.w700, s: 17)),
                              ),
                              const SizedBox(height: 4),
                              _label('Criações IA'),
                            ]),
                          ),
                        ),
                      for (final p in pk)
                        if (_byPkg(p) != null)
                          SizedBox(
                            width: 84,
                            child: Stack(clipBehavior: Clip.none, children: [
                              InkWell(
                                onTap: () => InstalledApps.startApp(p),
                                child: _appBody(_byPkg(p)!),
                              ),
                              if (_editing) _badge(() => _m.removeFromFolder(p)),
                            ]),
                          ),
                    ]),
                  ),
                ),
                if (pk.isEmpty && !isMedia)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Pasta vazia. Use EDITAR e + APP, ou mova apps pelo painel de Apps instalados.',
                        style: N.t(c: N.dim, s: 12)),
                  ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  /// Biblioteca das criações da IA (imagens e músicas salvas em Midia/).
  Future<void> _openLibrary() async {
    final list = await widget.media.library();
    if (!mounted) return;
    final player = AudioPlayer();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 520,
          height: 460,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: Text('Criações da IA',
                        style: N.t(c: N.cyan, w: FontWeight.w700, s: 15))),
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('FECHAR', style: N.t(c: N.dim, s: 12))),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text('Peça "crie uma música..." ou "gere uma imagem..." no console.',
                          style: N.t(c: N.dim)))
                  : GridView.count(
                      crossAxisCount: 4,
                      padding: const EdgeInsets.all(12),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        for (final m in list)
                          InkWell(
                            onTap: m.kind == 'music'
                                ? () => player.play(DeviceFileSource(m.path))
                                : null,
                            child: m.kind == 'image'
                                ? Image.file(File(m.path), fit: BoxFit.cover)
                                : Container(
                                    color: N.line2,
                                    alignment: Alignment.center,
                                    child: Text('TOCAR\n${m.path.split('/').last}',
                                        textAlign: TextAlign.center,
                                        style: N.t(c: N.violet, s: 10),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                          ),
                      ],
                    ),
            ),
          ]),
        ),
      ),
    );
    await player.dispose();
  }

  Widget _dockView() {
    if (_m.loading) return Center(child: Text('Carregando apps…', style: N.t(c: N.dim)));
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 14, runSpacing: 14, children: [
            for (var i = 0; i < _m.folders.length; i++) _rootTile(i),
            if (_editing && _m.folders.length < DockModel.maxFolders)
              InkWell(onTap: _newFolder, child: _addBox('+ pasta')),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Text(
            _editing
                ? 'Arraste uma pasta para reordenar. Abra uma pasta para renomear ou adicionar apps. Máximo de ${DockModel.maxFolders} pastas.'
                : '${_m.folders.length} de ${DockModel.maxFolders} pastas',
            style: N.t(c: N.dim, s: 11)),
      ),
    ]);
  }

  Widget _addBox(String t) => Container(
        width: 96,
        height: 66,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            border: Border.all(color: N.cyan), borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: N.t(c: N.cyan, w: FontWeight.w700, s: 12)),
      );

  Widget _browserView() => Column(children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _url,
                style: N.t(s: 12),
                cursorColor: N.cyan,
                textInputAction: TextInputAction.go,
                onSubmitted: _go,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: N.field,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: N.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: N.cyan)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            NBtn('LER PÁGINA', accent: true, onTap: _readPage),
          ]),
        ),
        Expanded(child: WebViewWidget(controller: _web)),
      ]);

  Widget _tab(String label, bool active, VoidCallback onTap, {bool small = false}) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: EdgeInsets.symmetric(horizontal: small ? 9 : 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? N.cyan : N.bg,
            border: Border.all(color: active ? N.cyan : N.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: N.t(c: active ? N.bg : N.dim, s: small ? 11 : 12, w: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line2))),
        child: Row(children: [
          _tab('DOCK', !_browser, () => setState(() => _browser = false)),
          _tab('NAVEGADOR', _browser, () => setState(() => _browser = true)),
          _tab('PLAY STORE', false, () => openStore()),
          const Spacer(),
          // Mesmo chip EDITAR do Hub de IAs.
          if (!_browser)
            _tab(_editing ? 'CONCLUIR' : 'EDITAR', _editing,
                () => setState(() => _editing = !_editing),
                small: true),
        ]),
      ),
      Expanded(child: _browser ? _browserView() : _dockView()),
    ]);
  }
}
