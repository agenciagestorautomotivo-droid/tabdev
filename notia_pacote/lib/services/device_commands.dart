import 'package:flutter/painting.dart';

import '../theme.dart';
import 'ai_router.dart';
import 'device_kit.dart';
import 'native_bridge.dart';
import 'notia_brain.dart';
import 'settings_store.dart';
import 'termux_service.dart';
import 'text_utils.dart';

/// Comandos de voz/texto que usam os recursos do aparelho. Tudo que dá para resolver
/// localmente é resolvido sem IA (0 tokens); a IA só entra para resumir e para o agente.
class DeviceCommands {
  DeviceCommands({
    required this.kit,
    required this.router,
    required this.brain,
    required this.settings,
    required this.say,
    required this.speak,
    required this.launch,
    required this.openImage,
    required this.openUrl,
  });
  final DeviceKit kit;
  final AiRouter router;
  final NotiaBrain brain;
  final SettingsStore settings;
  final void Function(String text, {Color color}) say;
  final void Function(String text) speak;
  final Future<String?> Function(String name) launch;
  final void Function(String path) openImage;
  final void Function(String url) openUrl;

  static const help = '''Recursos do aparelho:
• no <app>, <tarefa>  ou  agente: <tarefa>  → o Notia opera o app (PARAR na faixa do topo)
• notificações [app] · resumir notificações · limpar notificações · notif falar <app> / calar <app>
• ligar para <nome> · mensagem para <nome>: texto · whatsapp para <nome>: texto
• escanear (câmera → nota) · fotos de hoje · indexar galeria · achar foto <texto>
• agenda do aparelho · clip [texto] · compartilhar para o Notia (menu do Android)
• rotina: 07:00 resumir minha agenda · rotinas · rotina remover N
• lugar salvar casa · lugares · rotina: local casa => ...
• alarme 07:30 [nome] · próximo alarme (usa o Relógio do Android; toca com o app fechado)
• dev <pedido> (a IA cria e testa no Termux) · dev parar · dev status · termux <comando> · servir <pasta> [porta]
• scripts · script <nome> · prompts · prompt <nome> (biblioteca do PAINEL)
• conectores · conector <nome>: texto (webhooks do PAINEL)
• aparelho (status das permissões)''';

  Future<bool> handle(String text) async {
    final l = norm(text.trim());

    // ----- Ajuda e status -----
    if (l == 'ajuda' || l == 'recursos') {
      say(help, color: N.dim);
      return true;
    }
    if (l == 'aparelho' || l == 'permissoes') {
      await _status();
      return true;
    }

    // ----- Agente de apps -----
    if (l == 'parar' || l == 'pare' || l == 'parar agente') {
      if (kit.agent.running) {
        kit.agent.stop();
        say('Pedi para o agente parar.', color: N.amber);
      } else {
        say('Nenhum agente em execução.', color: N.dim);
      }
      return true;
    }
    final ag = RegExp(r'^agente\s*[:\-]?\s+(.+)$', caseSensitive: false).firstMatch(text.trim());
    if (ag != null) {
      await _agent(ag.group(1)!.trim(), null);
      return true;
    }
    final inApp = RegExp(
            r'^(?:no|na|usando o|usando a|use o|use a|pelo|pela)\s+([^,:]{2,30}?)\s*[,:]\s*(.{4,})$',
            caseSensitive: false)
        .firstMatch(text.trim());
    if (inApp != null && inApp.group(1)!.trim().split(' ').length <= 3) {
      await _agent(inApp.group(2)!.trim(), inApp.group(1)!.trim());
      return true;
    }

    // ----- Notificações -----
    final nt = RegExp(r'^notificacoes?(?:\s+(.+))?$').firstMatch(l);
    if (nt != null) {
      say(kit.notifs.listText(app: nt.group(1)), color: N.text);
      return true;
    }
    if (l == 'resumir notificacoes' || l == 'resuma as notificacoes') {
      final data = kit.notifs.forAi();
      if (data.isEmpty) {
        say('Nenhuma notificação guardada.', color: N.dim);
        return true;
      }
      try {
        final r = await router.ask(
            'Resuma estas notificações (app|título|texto) em até 5 linhas, destacando o que é urgente:\n$data');
        say(r.text, color: N.green);
        speak(r.text);
      } catch (e) {
        say('Falha: ${_clean(e)}', color: N.red);
      }
      return true;
    }
    if (l == 'limpar notificacoes') {
      await kit.notifs.clear();
      say('Notificações guardadas apagadas.', color: N.green);
      return true;
    }
    final nf = RegExp(r'^notif (falar|calar) (.+)$').firstMatch(l);
    if (nf != null) {
      final list = settings.notifSpeak.toList();
      final app = nf.group(2)!.trim();
      if (nf.group(1) == 'falar') {
        if (!list.contains(app)) list.add(app);
        say('Vou ler em voz alta as notificações de "$app".', color: N.green);
      } else {
        list.remove(app);
        say('Parei de ler as notificações de "$app".', color: N.green);
      }
      await settings.setNotifSpeak(list);
      return true;
    }

    // ----- Contatos, ligação e mensagens -----
    final dialM = RegExp(r'^(?:ligar|ligue|telefonar|chamar)\s+(?:para\s+|pro\s+|pra\s+)?(.+)$').firstMatch(l);
    if (dialM != null) {
      final c = await kit.phone.find(dialM.group(1)!);
      if (c == null) {
        say(kit.phone.lastError, color: N.amber);
      } else {
        say('Abrindo a ligação para ${c.name}. Toque em ligar.', color: N.green);
        await kit.phone.dial(c);
      }
      return true;
    }
    final msg = RegExp(
            r'^(?:(?:mandar|enviar|mande|envie)\s+)?(mensagem|sms|whatsapp|zap)\s+(?:para\s+|pro\s+|pra\s+)([^:]+?)\s*:\s*(.+)$')
        .firstMatch(l);
    if (msg != null) {
      final raw = RegExp(
              r'^(?:(?:mandar|enviar|mande|envie)\s+)?\S+\s+(?:para\s+|pro\s+|pra\s+)[^:]+:\s*(.+)$',
              caseSensitive: false)
          .firstMatch(text.trim());
      final body = raw?.group(1)?.trim() ?? msg.group(3)!;
      final c = await kit.phone.find(msg.group(2)!);
      if (c == null) {
        say(kit.phone.lastError, color: N.amber);
      } else {
        final wpp = msg.group(1) == 'whatsapp' || msg.group(1) == 'zap';
        say('Abri ${wpp ? 'o WhatsApp' : 'as mensagens'} para ${c.name} com o texto pronto. Toque em enviar.',
            color: N.green);
        await (wpp ? kit.phone.whatsapp(c, body) : kit.phone.sms(c, body));
      }
      return true;
    }

    // ----- Câmera e OCR -----
    if (RegExp(r'^(escanear|escaneie|ler documento|ler papel|foto para nota|ocr)$').hasMatch(l)) {
      say('Abrindo a câmera…', color: N.dim);
      final r = await kit.ocr.scanCamera();
      if (r == null) {
        say(kit.ocr.lastError.isEmpty ? 'Cancelado.' : kit.ocr.lastError, color: N.amber);
      } else {
        await saveScan(r.text, r.path);
      }
      return true;
    }

    // ----- Galeria -----
    final fotos = RegExp(r'^fotos? (?:de )?(hoje|ontem|semana|da semana)$').firstMatch(l);
    if (fotos != null) {
      final w = fotos.group(1)!;
      final files = await kit.gallery.recent(
          n: 8, within: w == 'hoje' ? const Duration(days: 1) : w == 'ontem' ? const Duration(days: 2) : const Duration(days: 7));
      if (files.isEmpty) {
        say('Não achei fotos nesse período.', color: N.amber);
      } else {
        say('${files.length} foto(s) recentes. Mostrando a mais nova.', color: N.green);
        openImage(files.first.path);
      }
      return true;
    }
    if (l == 'indexar galeria') {
      say('Lendo o texto das fotos mais recentes (no aparelho, sem gastar tokens)…', color: N.dim);
      final n = await kit.gallery.indexOcr(progress: (m) => say(m));
      say('Pronto: $n foto(s) novas indexadas.', color: N.green);
      return true;
    }
    final ach = RegExp(r'^(?:achar|buscar|procurar|encontrar) fotos? (?:de |com |sobre )?(.+)$').firstMatch(l);
    if (ach != null) {
      final found = await kit.gallery.search(ach.group(1)!);
      if (found.isEmpty) {
        say('Nada encontrado. Rode "indexar galeria" para ler o texto das fotos novas.', color: N.amber);
      } else {
        say('Achei ${found.length} foto(s). Mostrando a primeira.', color: N.green);
        openImage(found.first);
      }
      return true;
    }

    // ----- Agenda do aparelho -----
    if (l == 'agenda do aparelho' || l == 'agenda local') {
      final lines = await kit.localCal.upcoming();
      if (lines == null) {
        say(kit.localCal.lastError, color: N.amber);
      } else if (lines.isEmpty) {
        say('Sem compromissos nas próximas 24 h.', color: N.green);
      } else {
        say('Próximas 24 h:\n${lines.join('\n')}', color: N.green);
      }
      return true;
    }

    // ----- Histórico da área de transferência -----
    final cp = RegExp(r'^(?:clip|clipboard|historico de copia)(?:\s*[:\-]?\s*(.+))?$').firstMatch(l);
    if (cp != null) {
      final q = cp.group(1)?.trim();
      if (q == 'limpar') {
        await kit.clip.clear();
        say('Histórico da área de transferência apagado.', color: N.green);
        return true;
      }
      final r = (q == null || q.isEmpty) ? kit.clip.latest() : kit.clip.search(q);
      say(r.isEmpty ? 'Nada no histórico${kit.clip.enabled ? '' : ' (desligado em CONFIG)'}.' : r.map((e) => '• ${clip(e.replaceAll('\n', ' '), 100)}').join('\n'),
          color: N.text);
      return true;
    }

    // ----- Despertador (Relógio do Android) -----
    final al = RegExp(r'^(?:alarme|despertador|me acorde|acorde me)\s*(?:para|as|a|às)?\s*(\d{1,2})(?:[:h](\d{2}))?\s*h?\s*(.*)$')
        .firstMatch(l);
    if (al != null) {
      final h = int.parse(al.group(1)!);
      final m = int.tryParse(al.group(2) ?? '0') ?? 0;
      if (h > 23 || m > 59) {
        say('Horário inválido. Ex.: alarme 07:30 academia', color: N.amber);
        return true;
      }
      final label = al.group(3)!.trim().isEmpty ? 'OpenEXE' : al.group(3)!.trim();
      final ok = await NativeBridge.setAlarm(h, m, label);
      say(ok
          ? 'Alarme criado para ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} ($label). Ele toca pelo Relógio do Android, mesmo com o OpenEXE fechado.'
          : 'Não consegui criar o alarme. Abra o app Relógio uma vez e tente de novo.',
          color: ok ? N.green : N.red);
      return true;
    }
    if (l == 'proximo alarme' || l == 'alarmes' || l == 'alarme') {
      final n = await NativeBridge.nextAlarm();
      say(n == null
          ? 'Nenhum alarme ativo. Crie com: alarme 07:30'
          : 'Próximo alarme: ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')} (${n.day}/${n.month}).',
          color: N.cyan);
      return true;
    }

    // ----- TAB DEV-IA (Termux) -----
    final dv = RegExp(r'^dev(?:\s*:|\s)\s*(.+)$', caseSensitive: false).firstMatch(text.trim());
    if (dv != null) {
      final arg = dv.group(1)!.trim();
      final la = arg.toLowerCase();
      if (la == 'parar' || la == 'pare') {
        kit.dev.stop();
        say('Parando o agente de desenvolvimento…', color: N.amber);
        return true;
      }
      if (la == 'status') {
        final st = await TermuxService.state();
        say('Termux: ${st.installed ? 'instalado' : 'não instalado'} · permissão: ${st.perm ? 'ok' : 'falta'}'
            '${kit.dev.running ? ' · agente rodando' : ''}', color: N.text);
        return true;
      }
      await kit.dev.run(arg, say);
      return true;
    }
    final tx = RegExp(r'^termux\s+(.+)$', caseSensitive: false, dotAll: true).firstMatch(text.trim());
    if (tx != null) {
      final r = await kit.termux.run(tx.group(1)!, dir: settings.devDir);
      final o = r.tail(1800);
      say(r.error != null ? 'Erro: ${r.error}${o.isEmpty ? '' : '\n$o'}' : (o.isEmpty ? '(sem saída, código ${r.exit})' : o),
          color: r.ok ? N.text : N.amber);
      return true;
    }
    final sv = RegExp(r'^servir\s+(\S+)(?:\s+(\d{2,5}))?$', caseSensitive: false).firstMatch(text.trim());
    if (sv != null) {
      final port = sv.group(2) ?? '8080';
      final dir = sv.group(1)!.replaceAll(RegExp(r'[^A-Za-z0-9._/-]'), '');
      say('Subindo $dir na porta $port…', color: N.dim);
      final r = await kit.termux.run(
          'cd "$dir" && (pkill -f "http.server $port" 2>/dev/null; nohup python -m http.server $port >/dev/null 2>&1 &) ; sleep 1; echo ok',
          dir: settings.devDir);
      if (r.ok) {
        openUrl('http://localhost:$port');
        say('Aberto no Dock (http://localhost:$port).', color: N.green);
      } else {
        say('Não consegui subir: ${r.error ?? r.tail(300)}', color: N.red);
      }
      return true;
    }

    // ----- Biblioteca e conectores (PAINEL) -----
    if (l == 'scripts' || l == 'prompts') {
      final k = l == 'scripts' ? 'script' : 'prompt';
      final xs = kit.library.all.where((e) => e.kind == k).toList();
      say(xs.isEmpty ? 'Nada salvo. Crie no PAINEL > Scripts e prompts.' : xs.map((e) => '• ${e.name}').join('\n'),
          color: N.text);
      return true;
    }
    final sc = RegExp(r'^(script|prompt)\s+(.+)$', caseSensitive: false).firstMatch(text.trim());
    if (sc != null) {
      final kind = sc.group(1)!.toLowerCase();
      final it = kit.library.byName(sc.group(2)!, kind: kind);
      if (it == null) return false;
      say('Executando ${it.name}…', color: N.dim);
      final n = await kit.library.runItem(it);
      say(n == 0 ? 'Nada para executar.' : '${it.name}: $n comando(s) enviados.', color: N.green);
      return true;
    }
    if (l == 'conectores') {
      final cs = kit.connectors.all;
      say(cs.isEmpty ? 'Nenhum conector. Crie no PAINEL > Conectores.' : cs.map((e) => '• ${e.name}').join('\n'),
          color: N.text);
      return true;
    }
    final cn = RegExp(r'^conector\s+([^:]+):\s*(.+)$', caseSensitive: false).firstMatch(text.trim());
    if (cn != null) {
      final c = kit.connectors.byName(cn.group(1)!);
      if (c == null) {
        say('Conector "${cn.group(1)!.trim()}" não existe.', color: N.amber);
      } else {
        say('Enviando para ${c.name}…', color: N.dim);
        say(await kit.connectors.call(c, cn.group(2)!), color: N.text);
      }
      return true;
    }

    // ----- Rotinas e lugares -----
    if (l == 'rotinas') {
      final rs = kit.routines.all;
      say(rs.isEmpty
          ? 'Nenhuma rotina. Ex.: rotina: 07:00 resumir minha agenda'
          : [for (var i = 0; i < rs.length; i++) '${i + 1}. ${rs[i].active ? '' : '(pausada) '}${rs[i].label}: ${rs[i].command}'].join('\n'),
          color: N.text);
      return true;
    }
    final rm = RegExp(r'^rotina (remover|pausar) (\d+)$').firstMatch(l);
    if (rm != null) {
      final i = int.parse(rm.group(2)!) - 1;
      if (rm.group(1) == 'remover') {
        say(await kit.routines.removeAt(i) ? 'Rotina removida.' : 'Número inválido.', color: N.green);
      } else {
        await kit.routines.toggle(i);
        say('Rotina alternada (pausa/ativa).', color: N.green);
      }
      return true;
    }
    final ro = RegExp(r'^rotina\s*:\s*(.+)$', caseSensitive: false).firstMatch(text.trim());
    if (ro != null) {
      final r = kit.routines.parse(ro.group(1)!);
      if (r == null) {
        say('Não entendi. Exemplos:\nrotina: 07:00 resumir minha agenda\nrotina: carregador => drive: backup\nrotina: notif whatsapp => resumir notificações',
            color: N.amber);
      } else {
        await kit.routines.add(r);
        say('Rotina criada: ${r.label} → ${r.command}', color: N.green);
      }
      return true;
    }
    final ls = RegExp(r'^lugar (salvar|remover) (.+)$').firstMatch(l);
    if (ls != null) {
      if (ls.group(1) == 'salvar') {
        say('Pegando sua localização…', color: N.dim);
        final ok = await kit.places.saveHere(ls.group(2)!);
        say(ok ? 'Salvei "${ls.group(2)}" (raio de 150 m).' : kit.places.lastError,
            color: ok ? N.green : N.amber);
      } else {
        await kit.places.remove(ls.group(2)!);
        say('Lugar removido.', color: N.green);
      }
      return true;
    }
    if (l == 'lugares') {
      final p = kit.places.places;
      say(p.isEmpty ? 'Nenhum lugar salvo. Use: lugar salvar casa' : p.map((e) => '• ${e.name}').join('\n'),
          color: N.text);
      return true;
    }
    return false;
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> saveScan(String text, String imagePath) async {
    if (text.isEmpty) {
      say('Não achei texto na foto.', color: N.amber);
      return;
    }
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final titulo = 'Scan ${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}${two(n.minute)}';
    final img = imagePath.contains('NotiaVault')
        ? '\n\n![[${imagePath.split('/').last}]]'
        : '';
    final ok = await brain.saveNote(titulo, '$text$img');
    say('Li ${text.length} caracteres e salvei a nota "$titulo"${ok ? ' no Vault' : ' (só no SQLite; libere "Todos os arquivos")'}.',
        color: N.green);
  }

  Future<void> _agent(String goal, String? app) async {
    say('Agente: "$goal"${app != null ? ' (app: $app)' : ''}. Use PARAR na faixa do topo para interromper.',
        color: N.cyan);
    try {
      final r = await kit.agent.run(goal, app: app, launch: launch, log: (m) => say(m));
      if (r.startsWith('PERGUNTA:')) {
        say(r.substring(9).trim(), color: N.amber);
        speak(r.substring(9).trim());
      } else {
        say(r, color: N.green);
        speak(r);
      }
    } catch (e) {
      say('Falha: ${_clean(e)}', color: N.red);
    }
  }

  Future<void> _status() async {
    final a11y = await NativeBridge.a11yEnabled();
    final notif = await NativeBridge.notifEnabled();
    final vault = brain.vault.available;
    final lines = [
      'Controle de apps (acessibilidade): ${a11y ? 'ATIVO' : 'desligado'}',
      'Leitura de notificações: ${notif ? 'ATIVA (${kit.notifs.items.length} guardadas)' : 'desligada'}',
      'Vault (arquivos): ${vault ? 'liberado' : 'sem acesso'}',
      'Bateria: ${kit.power.level.value}%${kit.power.charging ? ' (carregando)' : ''}',
      'Rotinas: ${kit.routines.all.length} · Lugares: ${kit.places.places.length}',
      'Histórico da área de transferência: ${kit.clip.enabled ? 'ligado' : 'desligado'}',
      if (!a11y || !notif) 'Ative em CONFIG > Recursos do aparelho.',
    ];
    say(lines.join('\n'), color: N.text);
  }
}
