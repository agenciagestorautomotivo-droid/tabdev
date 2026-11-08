import 'package:sqflite/sqflite.dart';

import 'vault_service.dart';

/// Cérebro Notia. O Vault (arquivos Markdown) é a fonte da verdade das notas e da
/// memória; o SQLite é o índice rápido, o histórico e o cache. A IA consulta só o
/// SQLite (poucas chaves por prompt), então o prompt fica pequeno.
class NotiaBrain {
  NotiaBrain._(this._db, this.vault);
  final Database _db;
  final VaultService vault;

  static Future<NotiaBrain> open() async {
    final path = '${await getDatabasesPath()}/notia_brain.db';
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''
CREATE TABLE memorias_kv (
  chave TEXT PRIMARY KEY,
  valor TEXT NOT NULL,
  categoria TEXT,
  atualizado_em INTEGER
)''');
        await db.execute('''
CREATE TABLE historico_eventos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  acao TEXT NOT NULL,
  resumo TEXT NOT NULL,
  timestamp INTEGER
)''');
        await db.execute('''
CREATE TABLE credenciais_servicos (
  servico TEXT PRIMARY KEY,
  login TEXT NOT NULL,
  hash_senha TEXT NOT NULL,
  token_sessao TEXT,
  metadados TEXT
)''');
        await db.execute('''
CREATE TABLE cache_comandos (
  comando_hash TEXT PRIMARY KEY,
  resposta TEXT NOT NULL,
  expira_em INTEGER
)''');
        await _createCalcVars(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await _createCalcVars(db);
      },
    );
    final vault = VaultService();
    final brain = NotiaBrain._(db, vault);
    await vault.ensure();
    await brain.syncFromVault();
    return brain;
  }

  static Future<void> _createCalcVars(Database db) => db.execute('''
CREATE TABLE IF NOT EXISTS variaveis_calc (
  variavel TEXT PRIMARY KEY,
  valor REAL NOT NULL,
  descricao TEXT,
  atualizado_em INTEGER
)''');

  /// Tabelas que entram no backup da nuvem (credenciais e cache ficam de fora).
  static const syncTables = ['memorias_kv', 'historico_eventos', 'variaveis_calc'];

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ---------- Memórias KV ----------
  Future<void> setKv(String chave, String valor, {String? categoria}) async {
    await _db.insert(
      'memorias_kv',
      {'chave': chave, 'valor': valor, 'categoria': categoria, 'atualizado_em': _now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getKv(String chave) async {
    final r = await _db.query('memorias_kv',
        columns: ['valor'], where: 'chave = ?', whereArgs: [chave], limit: 1);
    return r.isEmpty ? null : r.first['valor'] as String;
  }

  /// Injeção cirúrgica: busca só as chaves pedidas.
  Future<Map<String, String>> getKvs(List<String> chaves) async {
    if (chaves.isEmpty) return {};
    final marks = List.filled(chaves.length, '?').join(',');
    final r = await _db.query('memorias_kv',
        columns: ['chave', 'valor'], where: 'chave IN ($marks)', whereArgs: chaves);
    return {for (final row in r) row['chave'] as String: row['valor'] as String};
  }

  /// Busca por prefixo de chave e trecho do valor (usado pelo índice de OCR da galeria).
  Future<List<Map<String, Object?>>> searchKv(String prefix, String term, {int limit = 20}) {
    final t = term.replaceAll('%', '').replaceAll('_', '');
    return _db.query('memorias_kv',
        columns: ['chave', 'valor'],
        where: 'chave LIKE ? AND valor LIKE ?',
        whereArgs: ['$prefix%', '%$t%'],
        limit: limit);
  }

  Future<void> deleteKv(String chave) =>
      _db.delete('memorias_kv', where: 'chave = ?', whereArgs: [chave]);

  // ---------- Variáveis da calculadora ----------
  Future<void> setVar(String nome, double valor, {String? descricao}) async {
    await _db.insert(
      'variaveis_calc',
      {'variavel': nome, 'valor': valor, 'descricao': descricao, 'atualizado_em': _now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, double>> getVars() async {
    final r = await _db.query('variaveis_calc');
    return {
      for (final row in r) row['variavel'] as String: (row['valor'] as num).toDouble()
    };
  }

  // ---------- Backup/restauração ----------
  Future<List<Map<String, Object?>>> exportTable(String t) {
    if (!syncTables.contains(t)) throw ArgumentError('tabela não permitida: $t');
    return _db.query(t);
  }

  Future<void> replaceTable(String t, List<Map> rows) async {
    if (!syncTables.contains(t)) throw ArgumentError('tabela não permitida: $t');
    await _db.transaction((tx) async {
      await tx.delete(t);
      for (final r in rows) {
        await tx.insert(t, Map<String, Object?>.from(r));
      }
    });
  }

  // ---------- Vault ----------
  /// Lê Memoria/ e Notas/ do Vault e atualiza o índice SQLite. Chame ao abrir o app e
  /// ao voltar ao primeiro plano: edições feitas por outro agente entram aqui.
  Future<void> syncFromVault() async {
    if (!await vault.ensure()) return;
    final mem = await vault.memoria();
    for (final e in mem.entries) {
      await setKv(e.key, e.value, categoria: 'memoria');
    }
    for (final n in await vault.notes()) {
      await setKv('nota:${n.key}', n.value, categoria: 'nota');
    }
  }

  // ---------- Notas ----------
  /// Mesmo formato de antes: chave 'nota:slug' e valor 'titulo\ncorpo'.
  Future<List<Map<String, Object?>>> notes() async {
    if (await vault.ensure()) {
      final list = await vault.notes();
      return [
        for (final n in list) {'chave': 'nota:${n.key}', 'valor': _titleAndBody(n.value)},
      ];
    }
    return _db.query('memorias_kv',
        where: 'categoria = ?', whereArgs: ['nota'], orderBy: 'atualizado_em DESC');
  }

  String _titleAndBody(String md) {
    final lines = md.trim().split('\n');
    var title = '';
    var i = 0;
    for (; i < lines.length; i++) {
      if (lines[i].startsWith('# ')) {
        title = lines[i].substring(2).trim();
        i++;
        break;
      }
    }
    final body = lines.skip(i).join('\n').trim();
    return '$title\n$body';
  }

  String slug(String s) => vault.slug(s);

  /// Grava no Vault (fonte da verdade) e indexa no SQLite. Retorna true se o arquivo
  /// foi gravado; false significa que só o SQLite recebeu a nota.
  Future<bool> saveNote(String titulo, String conteudo) async {
    final s = slug(titulo);
    await setKv('nota:$s', '$titulo\n$conteudo', categoria: 'nota');
    await logEvent('nota_salva', titulo);
    if (!await vault.ensure()) return false;
    final ok = await vault.writeNote(titulo, conteudo);
    if (ok) await vault.appendDiario('Nota salva: $titulo');
    return ok;
  }

  /// Fato atômico: SQLite + Memoria/<chave>.md
  Future<bool> remember(String chave, String valor) async {
    await setKv(chave, valor, categoria: 'memoria');
    if (!await vault.ensure()) return false;
    return vault.writeMemoria(chave, valor);
  }

  // ---------- Histórico ----------
  Future<void> logEvent(String acao, String resumo) async {
    await _db.insert(
        'historico_eventos', {'acao': acao, 'resumo': resumo, 'timestamp': _now});
  }

  Future<List<Map<String, Object?>>> recentEvents({int limit = 20}) =>
      _db.query('historico_eventos', orderBy: 'id DESC', limit: limit);

  // ---------- Cache de comandos (0 tokens) ----------
  String _hash(String s) {
    var h = 2166136261;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
    }
    return '${h.toRadixString(16)}-${s.length}';
  }

  Future<String?> cacheGet(String comando) async {
    final r = await _db.query('cache_comandos',
        where: 'comando_hash = ?', whereArgs: [_hash(comando)], limit: 1);
    if (r.isEmpty) return null;
    final exp = (r.first['expira_em'] as int?) ?? 0;
    if (exp < _now) {
      await _db.delete('cache_comandos',
          where: 'comando_hash = ?', whereArgs: [_hash(comando)]);
      return null;
    }
    return r.first['resposta'] as String;
  }

  Future<void> cachePut(String comando, String resposta,
      {Duration ttl = const Duration(minutes: 30)}) async {
    await _db.insert(
      'cache_comandos',
      {
        'comando_hash': _hash(comando),
        'resposta': resposta,
        'expira_em': _now + ttl.inMilliseconds,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- Resumo para o painel ----------
  Future<int> countKv() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM memorias_kv')) ?? 0;
  Future<int> countCache() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM cache_comandos')) ??
          0;
}
