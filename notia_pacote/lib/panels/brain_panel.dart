import 'package:flutter/material.dart';

import '../services/notia_brain.dart';
import '../theme.dart';

/// Q3: visualizador do cérebro (SQLite) e editor de notas com espelho em Markdown.
class BrainPanel extends StatefulWidget {
  const BrainPanel({super.key, required this.brain, required this.onSyncCloud});
  final NotiaBrain brain;
  final VoidCallback onSyncCloud;

  @override
  State<BrainPanel> createState() => _BrainPanelState();
}

class _BrainPanelState extends State<BrainPanel> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  List<Map<String, Object?>> _notes = [];
  List<Map<String, Object?>> _events = [];
  Map<String, double> _vars = {};
  int _kv = 0;
  int _cache = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final n = await widget.brain.notes();
    final e = await widget.brain.recentEvents(limit: 6);
    final k = await widget.brain.countKv();
    final c = await widget.brain.countCache();
    final v = await widget.brain.getVars();
    if (!mounted) return;
    setState(() {
      _notes = n;
      _events = e;
      _kv = k;
      _cache = c;
      _vars = v;
    });
  }

  void _open(Map<String, Object?> row) {
    final v = (row['valor'] as String?) ?? '';
    final i = v.indexOf('\n');
    setState(() {
      _title.text = i > 0 ? v.substring(0, i) : v;
      _body.text = i > 0 ? v.substring(i + 1) : '';
      _status = '';
    });
  }

  Future<void> _save() async {
    final t = _title.text.trim();
    if (t.isEmpty) {
      setState(() => _status = 'Dê um título à nota.');
      return;
    }
    final mirrored = await widget.brain.saveNote(t, _body.text.trim());
    setState(() => _status = mirrored
        ? 'Salvo no Vault (Notas/).'
        : 'Salvo no SQLite. Libere "Todos os arquivos" em CONFIG para gravar no Vault.');
    _reload();
  }

  void _new() => setState(() {
        _title.clear();
        _body.clear();
        _status = '';
      });

  InputDecoration _dec(String hint) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: N.field,
        hintText: hint,
        hintStyle: N.t(c: N.dim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: N.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: N.cyan)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 170,
                decoration:
                    const BoxDecoration(border: Border(right: BorderSide(color: N.line2))),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Text('$_kv memórias · $_cache em cache',
                          style: N.t(c: N.dim, s: 11)),
                    ),
                    for (final n in _notes)
                      InkWell(
                        onTap: () => _open(n),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Text(
                            ((n['chave'] as String?) ?? '').replaceFirst('nota:', '') +
                                '.md',
                            style: N.t(c: N.dim),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    if (_notes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text('Sem notas ainda.', style: N.t(c: N.dim, s: 12)),
                      ),
                    const Divider(color: N.line2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('Variáveis (calc)', style: N.t(c: N.cyan, s: 11)),
                    ),
                    for (final e in _vars.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        child: Text('${e.key} = ${e.value}',
                            style: N.t(c: N.amber, s: 11),
                            overflow: TextOverflow.ellipsis),
                      ),
                    if (_vars.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        child: Text('use: set nome = valor', style: N.t(c: N.dim, s: 11)),
                      ),
                    const Divider(color: N.line2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('Últimos eventos', style: N.t(c: N.cyan, s: 11)),
                    ),
                    for (final e in _events)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        child: Text('${e['acao']}: ${e['resumo']}',
                            style: N.t(c: N.dim, s: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      TextField(
                          controller: _title,
                          style: N.t(c: N.amber, w: FontWeight.w700),
                          cursorColor: N.cyan,
                          decoration: _dec('Título da nota')),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TextField(
                          controller: _body,
                          style: N.t(),
                          cursorColor: N.cyan,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: _dec('Escreva em Markdown…'),
                        ),
                      ),
                      if (_status.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_status, style: N.t(c: N.dim, s: 11)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: N.line2))),
          child: Row(
            children: [
              NBtn('Salvar', onTap: _save),
              const SizedBox(width: 8),
              NBtn('Nova nota', onTap: _new),
              const SizedBox(width: 8),
              NBtn('Sync Cloud', onTap: () {
                widget.onSyncCloud();
                Future.delayed(const Duration(seconds: 2), _reload);
              }),
            ],
          ),
        ),
      ],
    );
  }
}
