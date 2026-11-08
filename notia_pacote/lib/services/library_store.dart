import 'dart:convert';

import 'settings_store.dart';

/// Biblioteca do painel: prompts (texto enviado ao console) e scripts (um comando por linha).
class LibItem {
  LibItem(this.id, this.kind, this.name, this.body);
  final String id;
  String kind; // 'prompt' | 'script'
  String name;
  String body;
  bool get isScript => kind == 'script';
  Map<String, dynamic> toJson() => {'id': id, 'k': kind, 'n': name, 'b': body};
  static LibItem fromJson(Map<String, dynamic> j) =>
      LibItem('${j['id']}', '${j['k']}', '${j['n']}', '${j['b']}');
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
