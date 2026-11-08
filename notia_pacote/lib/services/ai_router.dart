import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'notia_brain.dart';
import 'settings_store.dart';

class AiResult {
  AiResult(this.text, this.badge);
  final String text;
  final String badge;
}

/// Qualquer IA que fale o formato OpenAI /chat/completions (Groq, Gemini, OpenRouter,
/// DeepSeek, Mistral, Together, Ollama local...). Basta URL base, modelo e chave.
class AiProvider {
  AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.key,
    this.timeout = const Duration(seconds: 10),
  });
  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String key;
  final Duration timeout;

  Uri get endpoint => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
}

/// Roteador universal. Ordem para tarefas simples: Groq, Gemini, OpenRouter, próprios.
/// Para tarefas complexas: o especialista escolhido (ou Gemini/OpenRouter) primeiro.
/// Cada provedor tem timeout; se falhar, passa para o próximo (circuit breaker).
class AiRouter {
  AiRouter(this.brain, this.settings);
  final NotiaBrain brain;
  final SettingsStore settings;

  List<AiProvider> providers() {
    final off = settings.aiDisabled;
    return _all().where((p) => !off.contains(p.id)).toList();
  }

  /// Todos os provedores configurados (inclusive os desligados no painel).
  List<AiProvider> allConfigured() => _all();

  List<AiProvider> _all() {
    final s = settings;
    return [
      if (s.groqKey.isNotEmpty)
        AiProvider(
            id: 'groq',
            name: 'groq ${s.groqModel}',
            baseUrl: 'https://api.groq.com/openai/v1',
            model: s.groqModel,
            key: s.groqKey,
            timeout: const Duration(seconds: 6)),
      if (s.geminiKey.isNotEmpty)
        AiProvider(
            id: 'gemini',
            name: 'gemini ${s.geminiModel}',
            baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
            model: s.geminiModel,
            key: s.geminiKey,
            timeout: const Duration(seconds: 12)),
      if (s.openrouterKey.isNotEmpty)
        AiProvider(
            id: 'openrouter',
            name: 'openrouter ${s.openrouterModel}',
            baseUrl: 'https://openrouter.ai/api/v1',
            model: s.openrouterModel,
            key: s.openrouterKey,
            timeout: const Duration(milliseconds: 3500)),
      for (final c in s.customProviders)
        if ((c['baseUrl'] ?? '').isNotEmpty && (c['model'] ?? '').isNotEmpty)
          AiProvider(
              id: (c['name'] ?? 'custom').toLowerCase(),
              name: '${c['name']} ${c['model']}',
              baseUrl: c['baseUrl']!,
              model: c['model']!,
              key: c['key'] ?? '',
              timeout: const Duration(seconds: 15)),
    ];
  }

  List<String> get providerIds => providers().map((p) => p.id).toList();

  bool _complex(String p) {
    final l = p.toLowerCase();
    if (p.length > 160) return true;
    const kw = ['roteiro', 'escreva', 'redija', 'analise', 'explique', 'compare', 'planeje'];
    return kw.any(l.contains);
  }

  bool _cacheable(String p) {
    final l = p.toLowerCase();
    const volatile = ['agora', 'hoje', 'hora', 'amanhã', 'amanha', 'clima', 'agenda'];
    return !volatile.any(l.contains);
  }

  List<AiProvider> _chain(bool complex, String? only) {
    final all = providers();
    if (only != null) return all.where((p) => p.id == only.toLowerCase()).toList();
    AiProvider? byId(String id) {
      for (final p in all) {
        if (p.id == id) return p;
      }
      return null;
    }

    final order = complex
        ? [
            if (settings.specialist != 'auto') settings.specialist,
            'gemini',
            'openrouter',
            ...all.map((p) => p.id).where((i) => i != 'groq'),
            'groq',
          ]
        : [
            'groq',
            'gemini',
            'openrouter',
            ...all.map((p) => p.id),
          ];
    final seen = <String>{};
    final out = <AiProvider>[];
    for (final id in order) {
      final p = byId(id);
      if (p != null && seen.add(p.id)) out.add(p);
    }
    return out;
  }

  Future<AiResult> ask(String prompt, {bool forceSpecialist = false, String? providerId}) async {
    final key = '${providerId ?? ''}|${prompt.trim().toLowerCase()}';
    final cached = await brain.cacheGet(key);
    if (cached != null) return AiResult(cached, '[cache · 0 tokens]');

    // Injeção cirúrgica: só as chaves de memória necessárias entram no prompt.
    final wanted = ['usuario_nome', 'preferencias'];
    if (RegExp(r'agenda|compromiss|reuni|hoje', caseSensitive: false).hasMatch(prompt)) {
      wanted.addAll(['agenda_hoje', 'agenda_local']);
    }
    final ctx = await brain.getKvs(wanted);
    final sys = StringBuffer('Você é o Notia. Responda em português, curto e direto.');
    ctx.forEach((k, v) => sys.write(' $k: $v.'));

    final chain = _chain(forceSpecialist || _complex(prompt), providerId);
    if (chain.isEmpty) {
      throw Exception(providerId != null
          ? 'Provedor "$providerId" não configurado.'
          : 'Nenhuma IA configurada. Em CONFIG, cole ao menos uma chave (Groq ou Gemini são grátis).');
    }

    final errs = <String>[];
    for (var i = 0; i < chain.length; i++) {
      final p = chain[i];
      try {
        final t = await _chat(p, sys.toString(), prompt,
            timeout: providerId != null ? const Duration(seconds: 30) : p.timeout);
        final res = AiResult(t, '[${p.name}${i > 0 ? ' · fallback' : ''}]');
        if (_cacheable(prompt)) await brain.cachePut(key, t);
        await brain.logEvent('ia', prompt.length > 80 ? prompt.substring(0, 80) : prompt);
        return res;
      } catch (e) {
        errs.add('${p.id}: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    throw Exception('Todas as IAs falharam → ${errs.join(' | ')}');
  }

  /// Passo de agente: sem cache, resposta curta e precisa. O Gemini vai primeiro
  /// (aceita telas maiores e segue o formato JSON melhor que modelos pequenos).
  Future<String> complete(String system, String user, {int maxTokens = 160}) async {
    final all = providers();
    if (all.isEmpty) {
      throw Exception('Nenhuma IA configurada. Em CONFIG, cole ao menos uma chave.');
    }
    AiProvider? byId(String id) {
      for (final p in all) {
        if (p.id == id) return p;
      }
      return null;
    }

    final seen = <String>{};
    final chain = <AiProvider>[];
    for (final id in ['gemini', 'groq', 'openrouter', ...all.map((p) => p.id)]) {
      final p = byId(id);
      if (p != null && seen.add(p.id)) chain.add(p);
    }
    final errs = <String>[];
    for (final p in chain) {
      try {
        return await _chat(p, system, user,
            timeout: const Duration(seconds: 25), maxTokens: maxTokens, temperature: 0.2);
      } catch (e) {
        errs.add('${p.id}: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    throw Exception('Todas as IAs falharam → ${errs.join(' | ')}');
  }

  Future<String> _chat(AiProvider p, String system, String user,
      {required Duration timeout, int maxTokens = 500, double temperature = 0.5}) async {
    final res = await http
        .post(
          p.endpoint,
          headers: {
            if (p.key.isNotEmpty) 'Authorization': 'Bearer ${p.key}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': p.model,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
            'temperature': temperature,
            'max_tokens': maxTokens,
          }),
        )
        .timeout(timeout);
    if (res.statusCode == 404 && p.id == 'gemini' && !_retried) {
      // O Google troca/aposenta nomes de modelo: descobre um válido e tenta de novo uma vez.
      final m = await _discoverGemini(p.key);
      if (m != null && m != p.model) {
        await settings.setGeminiModel(m);
        _retried = true;
        try {
          return await _chat(
              AiProvider(id: p.id, name: p.name, baseUrl: p.baseUrl, model: m, key: p.key, timeout: p.timeout),
              system, user,
              timeout: timeout, maxTokens: maxTokens, temperature: temperature);
        } finally {
          _retried = false;
        }
      }
    }
    if (res.statusCode != 200) {
      var body = utf8.decode(res.bodyBytes).replaceAll(RegExp(r'\s+'), ' ');
      if (body.length > 140) body = '${body.substring(0, 140)}…';
      throw Exception('${p.id} HTTP ${res.statusCode} ${p.model} $body');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return (data['choices'][0]['message']['content'] as String).trim();
  }

  bool _retried = false;

  /// Lista os modelos que a chave enxerga e escolhe o Flash estável mais novo.
  Future<String?> _discoverGemini(String key) async {
    try {
      final r = await http.get(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200'),
          headers: {'x-goog-api-key': key}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final list = (jsonDecode(utf8.decode(r.bodyBytes))['models'] as List? ?? []);
      final bad = RegExp(r'embed|image|tts|live|audio|thinking|vision|robotics|computer|aqa|imagen|veo|gemma|learnlm');
      String? best;
      double bestScore = -1;
      for (final m in list) {
        final methods = (m['supportedGenerationMethods'] as List? ?? []).map((e) => '$e').toList();
        final name = ('${m['name']}').replaceFirst('models/', '');
        if (!methods.contains('generateContent') || !name.startsWith('gemini') || bad.hasMatch(name)) continue;
        final v = double.tryParse(RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(name)?.group(1) ?? '') ?? 0;
        var sc = v * 10;
        if (name.contains('flash')) sc += 5;
        if (name.contains('lite')) sc -= 2;
        if (name.contains('pro')) sc -= 3;
        if (name.contains('preview') || name.contains('exp')) sc -= 4;
        if (RegExp(r'-\d{3}$').hasMatch(name)) sc -= 0.5;
        if (sc > bestScore) {
          bestScore = sc;
          best = name;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }
}
