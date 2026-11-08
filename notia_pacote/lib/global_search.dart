import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';

import 'services/clipboard_history_service.dart';
import 'services/dock_model.dart';
import 'services/notia_brain.dart';
import 'services/text_utils.dart';
import 'theme.dart';

class SearchHit {
  SearchHit(this.kind, this.title, this.sub, this.run);
  final String kind; // NOTA, APP, TEXTO, FOTO, COMANDO
  final String title;
  final String sub;
  final VoidCallback run;
}

/// Busca global (Ctrl K): notas do cérebro, apps instalados, comandos do console,
/// fotos indexadas por OCR e textos da área de transferência.
Future<void> showGlobalSearch(
  BuildContext context, {
  required NotiaBrain brain,
  required DockModel dock,
  required ClipboardHistoryService clip,
  required void Function(AppInfo app) onApp,
  required void Function(String cmd) onCommand,
  required void Function(String text) onText,
  required void Function(String title, String body) onNote,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _Search(
      brain: brain,
      dock: dock,
      clip: clip,
      onApp: onApp,
      onCommand: onCommand,
      onText: onText,
      onNote: onNote,
    ),
  );
}

class _Search extends StatefulWidget {
  const _Search({
    required this.brain,
    required this.dock,
    required this.clip,
    required this.onApp,
    required this.onCommand,
    required this.onText,
    required this.onNote,
  });
  final NotiaBrain brain;
  final DockModel dock;
  final ClipboardHistoryService clip;
  final void Function(AppInfo app) onApp;
  final void Function(String cmd) onCommand;
  final void Function(String text) onText;
  final void Function(String title, String body) onNote;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final _c = TextEditingController();
  List<SearchHit> _hits = [];
  int _seq = 0;

  static const _commands = [
    'ajuda', 'aparelho', 'escanear', 'notificações', 'rotinas', 'lugares', 'fotos de hoje',
    'indexar galeria', 'drive: backup', 'parar',
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final id = ++_seq;
    final q = norm(raw.trim());
    if (q.isEmpty) {
      setState(() => _hits = []);
      return;
    }
    final hits = <SearchHit>[];
    for (final a in widget.dock.all) {
      if (norm(a.name).contains(q)) {
        hits.add(SearchHit('APP', a.name, widget.dock.folderNameOf(a.packageName) ?? 'sem pasta',
            () => widget.onApp(a)));
        if (hits.where((h) => h.kind == 'APP').length >= 6) break;
      }
    }
    for (final c in _commands) {
      if (norm(c).contains(q)) hits.add(SearchHit('COMANDO', c, 'rodar no console', () => widget.onCommand(c)));
    }
    for (final t in widget.clip.search(raw, n: 4)) {
      hits.add(SearchHit('TEXTO', clip(t.replaceAll('\n', ' '), 80), 'área de transferência',
          () => widget.onText(t)));
    }
    try {
      for (final n in await widget.brain.notes()) {
        final v = '${n['valor']}';
        if (norm(v).contains(q) || norm('${n['chave']}').contains(q)) {
          final slug = '${n['chave']}'.replaceFirst('nota:', '');
          final i = v.indexOf('\n');
          final title = i > 0 ? v.substring(0, i) : slug;
          final body = i > 0 ? v.substring(i + 1) : v;
          hits.add(SearchHit('NOTA', title, clip(v.replaceAll('\n', ' '), 80),
              () => widget.onNote(title, body)));
          if (hits.where((h) => h.kind == 'NOTA').length >= 6) break;
        }
      }
      for (final r in await widget.brain.searchKv('ocr:', raw, limit: 5)) {
        hits.add(SearchHit('FOTO', clip('${r['valor']}'.replaceAll('\n', ' '), 80),
            '${r['chave']}'.replaceFirst('ocr:', ''), () => widget.onCommand('achar foto $raw')));
      }
    } catch (_) {}
    if (!mounted || id != _seq) return;
    setState(() => _hits = hits);
  }

  Color _color(String k) => switch (k) {
        'APP' => N.cyan,
        'NOTA' => N.green,
        'TEXTO' => N.amber,
        'FOTO' => N.violet,
        _ => N.dim,
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: N.bg,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 70, left: 24, right: 24),
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _c,
              autofocus: true,
              style: N.t(s: 15),
              cursorColor: N.cyan,
              onChanged: _search,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: N.field,
                hintText: 'Buscar notas, apps, comandos, fotos (OCR) e textos copiados',
                hintStyle: N.t(c: N.dim, s: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: N.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: N.cyan)),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: _hits.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(_c.text.isEmpty ? 'Digite para buscar. Esc fecha.' : 'Nada encontrado.',
                        style: N.t(c: N.dim)))
                : ListView(shrinkWrap: true, children: [
                    for (final h in _hits)
                      ListTile(
                        dense: true,
                        leading: SizedBox(
                            width: 64,
                            child: Text(h.kind, style: N.t(c: _color(h.kind), s: 10, w: FontWeight.w700))),
                        title: Text(h.title, style: N.t(), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(h.sub,
                            style: N.t(c: N.dim, s: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(context);
                          h.run();
                        },
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
