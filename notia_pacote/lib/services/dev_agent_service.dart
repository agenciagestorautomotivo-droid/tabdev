import 'dart:convert';

import 'package:flutter/painting.dart';

import '../theme.dart';
import 'ai_router.dart';
import 'ai_task_service.dart';
import 'settings_store.dart';
import 'termux_service.dart';

/// TAB DEV-IA: recebe um pedido ("crie um site de ...", "faça um app ..."), pede à IA os
/// comandos, roda no Termux, lê a saída e corrige os erros até ficar pronto.
class DevAgentService {
  DevAgentService(this.termux, this.router, this.settings, this.tasks);
  final TermuxService termux;
  final AiRouter router;
  final SettingsStore settings;
  final AiTaskService tasks;

  /// Mostra os comandos e devolve true para executar.
  Future<bool> Function(String explica, List<String> cmds)? confirm;

  bool running = false;
  bool _stop = false;
  void stop() => _stop = true;

  static const maxRounds = 8;

  static final _blocked = RegExp(
      r'rm\s+-[a-z]*r[a-z]*f?\s+(/|~|\$HOME|/data)(\s|$)|mkfs|dd\s+if=|:\(\)\s*\{|>\s*/dev/(sd|mmu|block)');
  static final _risky = RegExp(
      r'\brm\b|\bsudo\b|git\s+push|curl[^|]*\|\s*(sh|bash)|chmod\s+-R|--force|\bkill\b|\bpkill\b|\bmv\b');

  static const _system = '''Você é o agente de desenvolvimento do TAB DEV-IA, rodando no Termux (Linux, Android, sem root).
Pasta de projetos: ~/projetos (cada projeto numa subpasta; sempre faça "cd" para ela no mesmo comando).
Responda SOMENTE com JSON, sem texto fora dele:
{"explica":"o que vai fazer neste passo, 1 frase","comandos":["..."],"pronto":false,"resumo":""}
Regras:
- Comandos não interativos (pkg install -y, npm init -y, sem editores). Instale com pkg/pip/npm.
- Crie arquivos com: cat > caminho <<'EOF' ... EOF (um comando pode ter várias linhas).
- No máximo 6 comandos por passo. Um passo por vez; veja a saída e continue ou corrija.
- Se a saída anterior mostra erro, conserte antes de seguir.
- Quando terminar e testar, devolva "pronto":true e "resumo" com o que foi criado, a pasta e como rodar.
- Site/web: sirva com python -m http.server PORTA (use nohup ... & para ficar no fundo).
- Nunca apague fora da pasta do projeto.''';

  Map<String, dynamic>? _parse(String t) {
    final a = t.indexOf('{'), b = t.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(t.substring(a, b + 1)) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> run(String goal, void Function(String text, {Color color}) say) async {
    if (running) {
      say('Já tem um pedido de desenvolvimento rodando. Diga "dev parar" para cancelar.', color: N.amber);
      return;
    }
    final st = await TermuxService.state();
    if (!st.ready) {
      say(!st.installed
              ? 'O Termux não está instalado. Abra PAINEL > Dev e siga o preparo (uma vez).'
              : 'Falta liberar o Termux. Abra PAINEL > Dev > "Dar permissão".',
          color: N.amber);
      return;
    }
    running = true;
    _stop = false;
    final hist = <String>[];
    try {
      for (var round = 1; round <= maxRounds && !_stop; round++) {
        tasks.upsert('dev', 'Agente de desenvolvimento',
            detail: 'passo $round de até $maxRounds', progress: (round - 1) / maxRounds, onStop: stop);
        final user = StringBuffer('PEDIDO: $goal\n');
        if (hist.isNotEmpty) {
          user.writeln('\nHISTÓRICO (mais recente por último):');
          for (final h in hist.length > 4 ? hist.sublist(hist.length - 4) : hist) {
            user.writeln(h);
          }
        }
        String raw;
        try {
          raw = await router.complete(_system, user.toString(), maxTokens: 1800, useContext: true);
        } catch (e) {
          say('IA indisponível: ${e.toString().replaceFirst('Exception: ', '')}', color: N.red);
          tasks.finish('dev', result: 'Dev: IA indisponível', failed: true);
          return;
        }
        final j = _parse(raw);
        if (j == null) {
          hist.add('(resposta da IA não era JSON válido; responda só com o JSON pedido)');
          continue;
        }
        final cmds = [for (final c in (j['comandos'] as List? ?? [])) '$c'.trim()].where((c) => c.isNotEmpty).toList();
        final explica = '${j['explica'] ?? ''}'.trim();
        if (j['pronto'] == true && cmds.isEmpty) {
          say('Pronto. ${j['resumo'] ?? explica}', color: N.green);
          tasks.finish('dev', result: 'Dev concluído');
          return;
        }
        if (cmds.isEmpty) {
          hist.add('(nenhum comando; se terminou, devolva pronto:true)');
          continue;
        }
        if (cmds.any(_blocked.hasMatch)) {
          say('Bloqueei um comando perigoso e parei. Peça de outro jeito.', color: N.red);
          tasks.finish('dev', result: 'Dev: comando bloqueado', failed: true);
          return;
        }
        final ask = !settings.devAuto || cmds.any(_risky.hasMatch);
        if (explica.isNotEmpty) say('Dev: $explica', color: N.cyan);
        if (ask) {
          final ok = await (confirm?.call(explica, cmds) ?? Future.value(false));
          if (!ok) {
            say('Cancelado.', color: N.amber);
            tasks.finish('dev', result: 'Dev cancelado');
            return;
          }
        }
        for (final c in cmds) {
          if (_stop) break;
          final first = c.split('\n').first;
          say('\$ ${first.length > 100 ? '${first.substring(0, 100)}…' : first}', color: N.dim);
          final r = await termux.run(c, dir: settings.devDir);
          final out = r.tail(1200);
          if (out.isNotEmpty) say(out.length > 500 ? '…${out.substring(out.length - 500)}' : out, color: N.dim);
          hist.add('\$ $c\n[saída código ${r.exit}${r.error != null ? ', erro: ${r.error}' : ''}]\n$out');
          if (!r.ok) {
            say('Deu erro; vou tentar corrigir.', color: N.amber);
            break;
          }
        }
        if (j['pronto'] == true && hist.isNotEmpty && hist.last.contains('[saída código 0')) {
          say('Pronto. ${j['resumo'] ?? explica}', color: N.green);
          tasks.finish('dev', result: 'Dev concluído');
          return;
        }
      }
      say(_stop ? 'Parado.' : 'Parei depois de $maxRounds passos sem terminar. Veja o que foi feito e peça para continuar.',
          color: N.amber);
      tasks.finish('dev', result: _stop ? 'Dev parado' : 'Dev incompleto', failed: !_stop);
    } finally {
      running = false;
    }
  }
}
