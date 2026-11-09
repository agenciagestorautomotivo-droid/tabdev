import 'dart:convert';

import 'settings_store.dart';

/// Biblioteca do painel: prompts (texto enviado ao console) e scripts (um comando por linha).
class LibItem {
  LibItem(this.id, this.kind, this.name, this.body, {this.ctx = false});
  final String id;
  String kind; // 'prompt' | 'script'
  String name;
  String body;

  /// Instrução fixa: o texto entra em toda conversa com a IA.
  bool ctx;
  bool get isScript => kind == 'script';
  Map<String, dynamic> toJson() => {'id': id, 'k': kind, 'n': name, 'b': body, 'x': ctx};
  static LibItem fromJson(Map<String, dynamic> j) =>
      LibItem('${j['id']}', '${j['k']}', '${j['n']}', '${j['b']}', ctx: j['x'] == true);
}

class LibraryStore {
  LibraryStore(this.settings) {
    final raw = settings.libraryJson;
    if (raw.isEmpty) {
      _list = [
        LibItem('d1', 'prompt', 'Resumo do dia',
            'Resuma meu dia: agenda, tarefas pendentes e notificações importantes, em até 5 linhas.'),
        LibItem('d2', 'script', 'Bom dia',
            '# um comando por linha; # comenta\nresumir minha agenda\npróximo alarme\nresumir notificações'),
      ];
      return;
    }
    try {
      _list = [
        for (final e in jsonDecode(raw) as List) LibItem.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (_) {
      _list = [];
    }
  }
  final SettingsStore settings;
  late List<LibItem> _list;

  /// Executa uma linha como se fosse digitada no console.
  Future<void> Function(String line)? run;

  List<LibItem> get all => List.unmodifiable(_list);

  LibItem? byName(String name, {String? kind}) {
    final n = name.trim().toLowerCase();
    for (final i in _list) {
      if (i.name.toLowerCase() == n && (kind == null || i.kind == kind)) return i;
    }
    return null;
  }

  Future<void> _save() => settings.setLibraryJson(jsonEncode(_list.map((e) => e.toJson()).toList()));

  Future<void> upsert(LibItem it) async {
    final i = _list.indexWhere((e) => e.id == it.id);
    if (i >= 0) {
      _list[i] = it;
    } else {
      _list.add(it);
    }
    await _save();
  }

  Future<void> remove(String id) async {
    _list.removeWhere((e) => e.id == id);
    await _save();
  }

  /// Limite do que vai para a IA em toda conversa (~750 tokens).
  static const ctxLimit = 3000;

  int get ctxChars => _list.where((e) => e.ctx).fold(0, (a, e) => a + e.name.length + e.body.length + 6);

  /// Texto das instruções fixas para a IA (vazio se não houver nenhuma marcada).
  String contextText() {
    final b = StringBuffer();
    for (final e in _list.where((e) => e.ctx)) {
      final t = '## ${e.name}\n${e.body.trim()}\n';
      if (b.length + t.length > ctxLimit) {
        b.write(t.substring(0, (ctxLimit - b.length).clamp(0, t.length)));
        break;
      }
      b.write(t);
    }
    return b.toString().trim();
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Linhas executáveis do script (ignora vazias e comentários).
  static List<String> lines(String body) => [
        for (final l in body.split('\n'))
          if (l.trim().isNotEmpty && !l.trim().startsWith('#')) l.trim()
      ];

  Future<int> runItem(LibItem it) async {
    final r = run;
    if (r == null) return 0;
    final ls = it.isScript ? lines(it.body) : [it.body.trim()];
    var n = 0;
    for (final l in ls) {
      if (l.isEmpty) continue;
      await r(l);
      n++;
    }
    return n;
  }
}
