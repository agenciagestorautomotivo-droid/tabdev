enum IntentKind { music, image, video, none }

class Intent {
  Intent(this.kind, this.prompt);
  final IntentKind kind;
  final String prompt;
}

/// Reconhece pedidos de criação com regras locais: 0 tokens, resposta instantânea.
/// Só o que não casa aqui vai para um modelo de linguagem.
class IntentRouter {
  static final _verb = RegExp(
      r'\b(crie|cria|criar|gere|gera|gerar|fa[cç]a|fazer|compon(h|)a|compor|desenhe|produza|monte)\b',
      caseSensitive: false);
  static final _music =
      RegExp(r'm[úu]sica|trilha|beat|jingle|melodia|can[çc][ãa]o|\bsom\b', caseSensitive: false);
  static final _image = RegExp(
      r'imagem|foto\b|logo|ilustra[çc][ãa]o|\barte\b|desenho|banner|wallpaper|capa\b',
      caseSensitive: false);
  static final _video = RegExp(r'v[íi]deo|anima[çc][ãa]o|reels', caseSensitive: false);

  static Intent detect(String text) {
    if (!_verb.hasMatch(text)) return Intent(IntentKind.none, text);
    for (final e in [
      (IntentKind.music, _music),
      (IntentKind.image, _image),
      (IntentKind.video, _video),
    ]) {
      final m = e.$2.firstMatch(text);
      if (m != null) {
        var rest = text.substring(m.end).trim();
        rest = rest.replaceFirst(
            RegExp(r'^(de|do|da|sobre|com|para|pra|que|:|-)\s+', caseSensitive: false), '');
        return Intent(e.$1, rest.isEmpty ? text : rest);
      }
    }
    return Intent(IntentKind.none, text);
  }
}
