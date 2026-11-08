import 'dart:io';

/// Vault do Notia: uma pasta de arquivos Markdown no estilo Obsidian.
/// Qualquer agente que leia arquivos (Claude Code ou o app do Claude no computador,
/// o próprio Obsidian) pode abrir esta pasta e trabalhar nela, sem API.
///
/// Estrutura:
///   CLAUDE.md   instruções para o agente que abrir o Vault
///   Notas/      notas livres (uma por arquivo, com frontmatter)
///   Memoria/    fatos atômicos (um por arquivo, curtos) que o Notia injeta nos prompts
///   Diario/     um arquivo por dia (AAAA-MM-DD.md)
///   Inbox/      pedidos que um agente deixa para o Notia executar
///   Midia/      imagens e músicas criadas por IA (Imagens/, Musicas/)
class VaultService {
  static const root = '/sdcard/Documents/NotiaVault';
  static const _dirs = ['Notas', 'Memoria', 'Diario', 'Inbox'];

  bool available = false;

  /// Cria a estrutura. Retorna false se o Android negar acesso (permissão
  /// "Todos os arquivos" ainda não concedida).
  Future<bool> ensure() async {
    try {
      for (final d in _dirs) {
        await Directory('$root/$d').create(recursive: true);
      }
      final guide = File('$root/CLAUDE.md');
      if (!await guide.exists()) await guide.writeAsString(_guideText);
      available = true;
    } catch (_) {
      available = false;
    }
    return available;
  }

  String slug(String s) {
    final r = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final t = r.replaceAll(RegExp(r'^-+|-+$'), '');
    return t.isEmpty ? 'nota' : t;
  }

  String _stripFrontmatter(String raw) {
    if (!raw.startsWith('---')) return raw;
    final end = raw.indexOf('\n---', 3);
    if (end < 0) return raw;
    return raw.substring(end + 4).trimLeft();
  }

  Future<List<File>> _mdFiles(String dir) async {
    final d = Directory('$root/$dir');
    if (!await d.exists()) return [];
    final out = <File>[];
    await for (final e in d.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.md')) out.add(e);
    }
    out.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return out;
  }

  String _name(File f) {
    final n = f.uri.pathSegments.last;
    return n.endsWith('.md') ? n.substring(0, n.length - 3) : n;
  }

  /// Notas: lista (slug, texto sem frontmatter), mais recentes primeiro.
  Future<List<MapEntry<String, String>>> notes({int limit = 200}) async {
    final out = <MapEntry<String, String>>[];
    for (final f in (await _mdFiles('Notas')).take(limit)) {
      out.add(MapEntry(_name(f), _stripFrontmatter(await f.readAsString())));
    }
    return out;
  }

  Future<bool> writeNote(String titulo, String conteudo) async {
    try {
      final now = DateTime.now().toIso8601String();
      final f = File('$root/Notas/${slug(titulo)}.md');
      var criado = now;
      if (await f.exists()) {
        final m = RegExp(r'criado: (.+)').firstMatch(await f.readAsString());
        if (m != null) criado = m.group(1)!.trim();
      }
      await f.writeAsString('---\ntitulo: $titulo\ncriado: $criado\natualizado: $now\ntags: []\n---\n\n# $titulo\n\n$conteudo\n');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Memória atômica: Memoria/<chave>.md, um fato por arquivo.
  Future<Map<String, String>> memoria() async {
    final out = <String, String>{};
    for (final f in await _mdFiles('Memoria')) {
      var v = _stripFrontmatter(await f.readAsString()).trim();
      if (v.length > 500) v = v.substring(0, 500);
      out[_name(f)] = v;
    }
    return out;
  }

  Future<bool> writeMemoria(String chave, String valor) async {
    try {
      await File('$root/Memoria/${slug(chave)}.md').writeAsString('$valor\n');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> appendDiario(String texto) async {
    try {
      final n = DateTime.now();
      String two(int x) => x.toString().padLeft(2, '0');
      final f = File('$root/Diario/${n.year}-${two(n.month)}-${two(n.day)}.md');
      await f.writeAsString('- ${two(n.hour)}:${two(n.minute)} $texto\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  Future<List<String>> inboxItems() async {
    final out = <String>[];
    for (final f in await _mdFiles('Inbox')) {
      out.add(_name(f));
    }
    return out;
  }

  static const _guideText = '''# Vault do Notia

Esta pasta é a memória do Notia, o launcher do tablet. Você (agente) pode ler e
escrever aqui. Siga estas regras para o Notia continuar entendendo o conteúdo.

## Pastas
- `Notas/`: notas livres, uma por arquivo, com frontmatter (titulo, criado, atualizado, tags).
- `Memoria/`: fatos atômicos. Um fato por arquivo, no máximo 300 caracteres.
  O nome do arquivo é a chave (ex.: `usuario_nome.md`). O Notia lê só estes arquivos
  para montar os prompts, então mantenha curto.
- `Diario/`: um arquivo por dia (`AAAA-MM-DD.md`), uma linha por evento.
- `Inbox/`: pedidos para o Notia. Um arquivo por pedido, texto curto e claro.
- `Midia/`: imagens e músicas geradas por IA. Não edite; pode ler e referenciar.

## Regras
- Escreva em português do Brasil.
- Use links no estilo Obsidian: `[[nome-da-nota]]`.
- Não renomeie nem apague `CLAUDE.md`.
- Não coloque senhas, chaves de API ou dados bancários no Vault.
- Antes de reescrever uma nota, leia a versão atual; preserve o frontmatter.
''';
}
