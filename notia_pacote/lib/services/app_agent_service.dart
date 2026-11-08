import 'dart:async';
import 'dart:convert';

import 'ai_router.dart';
import 'native_bridge.dart';
import 'notia_brain.dart';

/// Agente que opera outros apps como uma pessoa: lê a tela (acessibilidade), pede UMA
/// ação por vez à IA, executa, e repete até concluir. Tem limite de passos, botão
/// PARAR sempre visível, recusa campos de senha e pede sua confirmação antes de
/// qualquer ação sensível (pagar, enviar, apagar, assinar...).
class AppAgentService {
  AppAgentService(this.router, this.brain);
  final AiRouter router;
  final NotiaBrain brain;

  bool running = false;
  bool _stop = false;

  /// Progresso para a barra de tarefas da IA: (passo, máximo, texto).
  void Function(int step, int max, String msg)? onProgress;
  void Function()? onDone;
  String lastError = '';

  void stop() => _stop = true;

  /// Apps que o agente nunca opera (bancos, carteiras, cofres de senha).
  static const blockedPackages = [
    'nubank', 'itau', 'bradesco', 'santander', 'br.com.bb', 'caixa', 'inter.', 'picpay',
    'mercadopago', 'paypal', 'binance', 'authenticator', 'bitwarden', '1password',
    'lastpass', 'keepass', 'wallet',
  ];

  static final _sensitive = RegExp(
      r'pagar|pagamento|comprar|compra|finalizar|confirmar pedido|assinar|assinatura|'
      r'enviar|send|excluir|apagar|deletar|delete|remover|transferir|transfer|pix|'
      r'sair da conta|encerrar|cancelar plano|place order|buy|pay|subscribe|upgrade|'
      r'publicar|postar|aceitar e|concordo',
      caseSensitive: false);

  static const _system = '''Você controla um app Android tocando na tela, como uma pessoa faria.
Responda SOMENTE um JSON, sem texto extra, com UMA ação:
{"a":"tocar","id":N}
{"a":"digitar","id":N,"texto":"..."}
{"a":"rolar","dir":"baixo"}  (ou "cima")
{"a":"voltar"}
{"a":"esperar"}
{"a":"abrir","app":"nome do app"}
{"a":"fim","resumo":"o que foi feito"}  (objetivo cumprido, ou impossível)
{"a":"perguntar","texto":"o que precisa do usuário"}  (senha, código, escolha)
A tela vem como linhas "id:tipo:texto". Tipos: btn, txt, input, check, img. "*" = rolável.
Regras: use só ids da tela atual; nunca invente ids; nunca digite senhas; se a tela não mudou
depois da sua ação, tente outra coisa; quando concluir, responda fim.''';

  Map<String, dynamic>? _parse(String raw) {
    final a = raw.indexOf('{');
    final b = raw.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      final j = jsonDecode(raw.substring(a, b + 1));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  String _clip(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

  /// Executa o objetivo. Retorna o resumo final (ou uma pergunta ao usuário).
  /// [launch] abre um app pelo nome e devolve o nome aberto (ou null).
  Future<String> run(
    String goal, {
    String? app,
    required Future<String?> Function(String name) launch,
    required void Function(String msg) log,
    int maxSteps = 14,
  }) async {
    if (running) throw Exception('O agente já está trabalhando. Toque em PARAR primeiro.');
    if (!await NativeBridge.a11yEnabled()) {
      throw Exception(
          'O controle de apps está desligado. Em CONFIG > Controle de apps, ative o serviço de acessibilidade do Notia.');
    }
    running = true;
    _stop = false;
    var cur = 0;
    final rawLog = log;
    log = (m) {
      rawLog(m);
      onProgress?.call(cur, maxSteps, m.replaceFirst(RegExp(r'^passo \d+: '), ''));
    };
    onProgress?.call(0, maxSteps, 'Iniciando');
    lastError = '';
    final history = <String>[];
    var emptyCount = 0;
    var sameCount = 0;
    String? lastAction;
    String? lastPrint;

    try {
      await NativeBridge.overlay('Notia agindo…');
      if (app != null && app.isNotEmpty) {
        final opened = await launch(app);
        if (opened == null) return 'Não achei "$app" instalado.';
        log('Abri $opened.');
        history.add('abri $opened');
        await Future.delayed(const Duration(milliseconds: 2500));
      }

      for (var step = 1; step <= maxSteps; step++) {
        cur = step;
        onProgress?.call(step, maxSteps, 'Lendo a tela');
        if (_stop) return 'Parei a pedido seu.';
        final snap = await NativeBridge.snapshot();
        if (snap == null) return 'Não consegui ler a tela.';
        final pkg = snap.pkg.toLowerCase();
        if (blockedPackages.any(pkg.contains)) {
          await NativeBridge.home();
          return 'Esse app (${snap.pkg}) é sensível (banco, carteira ou senhas). Não opero.';
        }
        if (snap.nodes.isEmpty) {
          emptyCount++;
          if (emptyCount >= 3) {
            return 'A tela está vazia ou protegida contra leitura. Não consigo continuar aqui.';
          }
          await Future.delayed(const Duration(milliseconds: 1500));
          continue;
        }
        emptyCount = 0;

        final screen = snap.toPrompt();
        final unchanged = screen == lastPrint;
        lastPrint = screen;
        await NativeBridge.overlay('Notia · passo $step/$maxSteps');

        final user = StringBuffer()
          ..writeln('Objetivo: $goal')
          ..writeln('App: ${snap.pkg}');
        if (history.isNotEmpty) {
          user.writeln('Ações anteriores: ${history.skip(history.length > 6 ? history.length - 6 : 0).join(' → ')}');
        }
        if (unchanged) user.writeln('ATENÇÃO: a tela não mudou desde a última ação.');
        user
          ..writeln('Tela:')
          ..write(_clip(screen, 3500));

        Map<String, dynamic>? act;
        for (var attempt = 0; attempt < 2 && act == null; attempt++) {
          final raw = await router.complete(_system, user.toString());
          act = _parse(raw);
        }
        if (act == null) return 'A IA não respondeu no formato esperado. Tente de novo ou use outro modelo (@gemini).';

        final key = jsonEncode(act);
        sameCount = key == lastAction ? sameCount + 1 : 0;
        lastAction = key;
        if (sameCount >= 2) return 'Travei repetindo a mesma ação. Parei por segurança.';

        final kind = '${act['a']}';
        final id = act['id'] is num ? (act['id'] as num).toInt() : -1;
        final node = snap.byId(id);
        var okExec = true;

        switch (kind) {
          case 'fim':
            final r = '${act['resumo'] ?? 'Concluído.'}';
            await brain.vault.appendDiario('Agente: $goal → $r');
            await brain.logEvent('agente', _clip(goal, 80));
            return r;
          case 'perguntar':
            return 'PERGUNTA: ${act['texto'] ?? 'Preciso de uma informação sua.'}';
          case 'tocar':
            if (node == null) {
              history.add('tocar $id (id inválido)');
              continue;
            }
            if (_sensitive.hasMatch(node.text)) {
              final ok = await NativeBridge.confirmOverlay(
                  'O Notia quer tocar em "${node.text}". Permitir?');
              if (_stop) return 'Parei a pedido seu.';
              if (!ok) return 'Cancelei: você não confirmou "${node.text}".';
            }
            log('passo $step: tocar "${_clip(node.text, 30)}"');
            okExec = await NativeBridge.click(id);
            history.add('tocar "${_clip(node.text, 20)}"${okExec ? '' : ' (falhou)'}');
            await Future.delayed(const Duration(milliseconds: 1000));
          case 'digitar':
            if (node == null || node.kind != 'input') {
              history.add('digitar $id (não é campo)');
              continue;
            }
            if (node.password) {
              return 'PERGUNTA: o app pediu uma senha. Digite você mesmo e peça para eu continuar.';
            }
            final txt = '${act['texto'] ?? ''}';
            log('passo $step: digitar "${_clip(txt, 30)}"');
            okExec = await NativeBridge.setText(id, txt);
            history.add('digitei "${_clip(txt, 20)}"${okExec ? '' : ' (falhou)'}');
            await Future.delayed(const Duration(milliseconds: 700));
          case 'rolar':
            log('passo $step: rolar');
            okExec = await NativeBridge.scroll('${act['dir']}' != 'cima');
            history.add('rolei ${act['dir'] ?? 'baixo'}');
            await Future.delayed(const Duration(milliseconds: 800));
          case 'voltar':
            log('passo $step: voltar');
            await NativeBridge.back();
            history.add('voltei');
            await Future.delayed(const Duration(milliseconds: 800));
          case 'esperar':
            history.add('esperei');
            await Future.delayed(const Duration(milliseconds: 2000));
          case 'abrir':
            final name = '${act['app'] ?? ''}';
            final opened = await launch(name);
            history.add(opened != null ? 'abri $opened' : 'não achei $name');
            log(opened != null ? 'passo $step: abri $opened' : 'passo $step: não achei "$name"');
            await Future.delayed(const Duration(milliseconds: 2500));
          default:
            history.add('ação desconhecida "$kind"');
        }
      }
      return 'Cheguei ao limite de $maxSteps passos sem terminar. Veja onde parou e diga o que fazer.';
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      running = false;
      onDone?.call();
      await NativeBridge.overlay('', show: false);
      await NativeBridge.home();
    }
  }
}
