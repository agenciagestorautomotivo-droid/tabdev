import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_router.dart';
import 'settings_store.dart';

class WebHit {
  WebHit(this.title, this.url, {this.snippet = '', this.source = '', this.date = ''});
  final String title;
  final String url;
  final String snippet;
  final String source;
  final String date;
}

class WebAnswer {
  WebAnswer(this.text, this.sources, this.via);
  final String text;
  final List<WebHit> sources;
  final String via;
}

/// Internet para a IA: busca do Google via Gemini (melhor), ou notícias + pesquisa na web
/// resumidas por qualquer IA, ou, no pior caso, a lista de manchetes.
class WebService {
  WebService(this.router, this.settings);
  final AiRouter router;
  final SettingsStore settings;

  static const _ua = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Tablet) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.5',
  };

  static final _need = RegExp(
      r'not[ií]cias?|manchetes?|[uú]ltimas not|pesquis[ae]|busc[ae] (na|no|por)|procur[ae] na|na internet|na web|no google|'
      r'cota[cç][aã]o|d[oó]lar|bitcoin|previs[aã]o do tempo|clima (em|de|no|na)|placar|resultado d[eo] jogo|quem ganhou|'
      r'o que (aconteceu|houve|rolou)|lan[cç]amento d|pre[cç]o d[eo]|quando (sai|foi|vai)\b|^web[: ]|^/web ',
      caseSensitive: false);

  static bool shouldUse(String t) => _need.hasMatch(t.trim());

  static String _unesc(String s) => s
      .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const _stop = {
    'me', 'envie', 'enviar', 'mande', 'manda', 'pode', 'voce', 'você', 'por', 'favor', 'quero', 'gostaria', 'pesquise',
    'pesquisar', 'pesquisa', 'busque', 'buscar', 'procure', 'sobre', 'as', 'os', 'a', 'o', 'de', 'do', 'da', 'dos', 'das',
    'um', 'uma', 'para', 'pra', 'que', 'quando', 'pedi', 'deu', 'erro', 'na', 'no', 'em', 'mensagem', 'internet', 'web',
    'google', 'e', 'ou', 'com', 'se', 'ter', 'pode', 'acontecido', 'oque', 'faz', 'fazer', 'diga', 'conte', 'fale',
  };
  static const _generic = {'noticias', 'notícias', 'noticia', 'notícia', 'ultimas', 'últimas', 'hoje', 'domingo', 'segunda', 'terça', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'sábado', 'agora', 'manchetes'};

  static List<String> _kw(String q) => q
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_stop.contains(w))
      .toList();

  // ---------- Fontes ----------
  Future<List<WebHit>> news(String q) async {
    final kw = _kw(q);
    final topic = kw.where((w) => !_generic.contains(w)).toList();
    final url = topic.isEmpty
        ? 'https://news.google.com/rss?hl=pt-BR&gl=BR&ceid=BR:pt-419'
        : 'https://news.google.com/rss/search?q=${Uri.encodeQueryComponent(kw.join(' '))}&hl=pt-BR&gl=BR&ceid=BR:pt-419';
    final r = await http.get(Uri.parse(url), headers: _ua).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return [];
    final xml = utf8.decode(r.bodyBytes);
    final out = <WebHit>[];
    for (final m in RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml)) {
      final it = m.group(1)!;
      String tag(String t) => RegExp('<$t[^>]*>(.*?)</$t>', dotAll: true).firstMatch(it)?.group(1) ?? '';
      var title = _unesc(tag('title'));
      final src = _unesc(tag('source'));
      if (src.isNotEmpty && title.endsWith(' - $src')) title = title.substring(0, title.length - src.length - 3);
      out.add(WebHit(title, _unesc(tag('link')), source: src, date: _unesc(tag('pubDate'))));
      if (out.length >= 10) break;
    }
    return out;
  }

  Future<List<WebHit>> search(String q) async {
    final r = await http
        .get(Uri.parse('https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(_kw(q).join(' '))}&kl=br-pt'),
            headers: _ua)
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return [];
    final html = utf8.decode(r.bodyBytes);
    final parts = html.split('class="result__a"');
    final out = <WebHit>[];
    for (var i = 1; i < parts.length && out.length < 8; i++) {
      final seg = parts[i];
      final href = RegExp(r'href="([^"]+)"').firstMatch(seg)?.group(1) ?? '';
      var link = href;
      final u = RegExp(r'uddg=([^&"]+)').firstMatch(href)?.group(1);
      if (u != null) link = Uri.decodeComponent(u);
      if (link.startsWith('//')) link = 'https:$link';
      final title = _unesc(RegExp(r'>(.*?)</a>', dotAll: true).firstMatch(seg)?.group(1) ?? '');
      final sn = _unesc(RegExp(r'class="result__snippet"[^>]*>(.*?)</a>', dotAll: true).firstMatch(seg)?.group(1) ?? '');
      if (title.isEmpty || !link.startsWith('http')) continue;
      out.add(WebHit(title, link, snippet: sn, source: Uri.tryParse(link)?.host ?? ''));
    }
    return out;
  }

  Future<String> fetchText(String url, {int max = 3500}) async {
    try {
      final r = await http.get(Uri.parse(url), headers: _ua).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return '';
      var h = utf8.decode(r.bodyBytes, allowMalformed: true);
      final art = RegExp(r'<article[\s\S]*?</article>').firstMatch(h)?.group(0);
      if (art != null && art.length > 600) h = art;
      h = h.replaceAll(RegExp(r'<(script|style|nav|footer|header|noscript)[\s\S]*?</\1>', caseSensitive: false), ' ');
      final t = _unesc(h);
      return t.length > max ? t.substring(0, max) : t;
    } catch (_) {
      return '';
    }
  }

  // ---------- Google Search via Gemini ----------
  Future<WebAnswer?> _grounded(String q, {bool retry = true}) async {
    final key = settings.geminiKey;
    if (key.isEmpty || settings.aiDisabled.contains('gemini')) return null;
    final model = settings.geminiModel;
    final r = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
          headers: {'x-goog-api-key': key, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {
                  'text': 'Você é o Notia. Use a busca do Google para responder com informações atuais. '
                      'Responda em português do Brasil, objetivo, com datas quando houver. Hoje é ${_hoje()}.'
                      '${router.userContext?.call().isNotEmpty == true ? '\nInstruções do usuário: ${router.userContext!.call()}' : ''}'
                }
              ]
            },
            'contents': [
              {
                'parts': [
                  {'text': q}
                ]
              }
            ],
            'tools': [
              {'google_search': {}}
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (r.statusCode == 404 && retry) {
      final m = await router.discoverGemini();
      if (m != null && m != model) {
        await settings.setGeminiModel(m);
        return _grounded(q, retry: false);
      }
    }
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final cand = (j['candidates'] as List?)?.first;
    if (cand == null) return null;
    final text = [for (final p in (cand['content']?['parts'] as List? ?? [])) '${p['text'] ?? ''}'].join().trim();
    if (text.isEmpty) return null;
    final srcs = <WebHit>[];
    for (final c in (cand['groundingMetadata']?['groundingChunks'] as List? ?? [])) {
      final w = c['web'];
      if (w != null) srcs.add(WebHit('${w['title'] ?? ''}', '${w['uri'] ?? ''}'));
    }
    return WebAnswer(text, srcs, 'google via gemini');
  }

  static String _hoje() {
    final n = DateTime.now();
    const d = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
    return '${d[n.weekday - 1]}, ${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year}';
  }

  // ---------- Resposta ----------
  Future<WebAnswer> answer(String question) async {
    final q = question.replaceFirst(RegExp(r'^(/web|web:?)\s+', caseSensitive: false), '').trim();
    try {
      final g = await _grounded(q);
      if (g != null) return g;
    } catch (_) {/* cai para o plano B */}

    final newsy = RegExp(r'not[ií]cia|manchete|[uú]ltimas', caseSensitive: false).hasMatch(q);
    final hits = <WebHit>[];
    final res = await Future.wait<List<WebHit>>([
      news(q).catchError((_) => <WebHit>[]),
      if (!newsy || _kw(q).where((w) => !_generic.contains(w)).isNotEmpty) search(q).catchError((_) => <WebHit>[]),
    ]);
    for (final l in res) {
      hits.addAll(l);
    }
    if (hits.isEmpty) {
      throw Exception('Não consegui acessar a internet agora (notícias e pesquisa sem resposta).');
    }
    // Lê o texto das 2 primeiras páginas de pesquisa (links de notícias do Google não abrem por aqui).
    final pages = <String>[];
    for (final h in hits.where((h) => !h.url.contains('news.google.com')).take(2)) {
      final t = await fetchText(h.url);
      if (t.length > 300) pages.add('[${h.title}] $t');
    }
    final b = StringBuffer('PERGUNTA: $q\nHOJE: ${_hoje()}\n\nRESULTADOS:\n');
    var n = 1;
    for (final h in hits.take(12)) {
      b.writeln('$n. ${h.title}${h.source.isEmpty ? '' : ' (${h.source})'}${h.date.isEmpty ? '' : ' — ${h.date}'}'
          '${h.snippet.isEmpty ? '' : '\n   ${h.snippet}'}');
      n++;
    }
    if (pages.isNotEmpty) b.writeln('\nTEXTO DAS PÁGINAS:\n${pages.join('\n\n')}');
    try {
      final t = await router.complete(
          'Você é o Notia. Responda em português do Brasil, usando SOMENTE os resultados fornecidos. '
          'Seja objetivo; para notícias, liste as principais em tópicos curtos com a fonte. '
          'Se os resultados não bastarem, diga isso.',
          b.toString(),
          maxTokens: 900,
          useContext: true);
      return WebAnswer(t.trim(), hits.take(8).toList(), 'web + IA');
    } catch (_) {
      // As IAs estão lentas: entrega ao menos as manchetes.
      final lines = hits.take(8).map((h) => '• ${h.title}${h.source.isEmpty ? '' : ' (${h.source})'}').join('\n');
      return WebAnswer('As IAs estão lentas agora; aqui estão os resultados que encontrei:\n$lines', hits.take(8).toList(), 'web (sem IA)');
    }
  }
}
