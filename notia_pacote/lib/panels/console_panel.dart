import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart' hide Intent;
import 'package:flutter/services.dart';

import '../services/ai_task_service.dart';
import '../services/keyboard_mode.dart';
import '../services/tts_service.dart';
import '../services/voice_service.dart';
import '../services/ai_router.dart';
import '../services/device_commands.dart';
import '../services/device_kit.dart';
import '../services/github_sync_service.dart';
import '../services/google_services.dart';
import '../services/hybrid_calculator_service.dart';
import '../services/intent_router.dart';
import '../services/media_service.dart';
import '../services/notia_brain.dart';
import '../services/settings_store.dart';
import '../services/supabase_sync_service.dart';
import '../theme.dart';

class _Msg {
  _Msg(this.text,
      {this.badge, this.color = N.text, this.user = false, this.mediaPath, this.mediaKind});
  final String text;
  final String? badge;
  final Color color;
  final bool user;
  final String? mediaPath;
  final String? mediaKind;
}

/// Q1: console universal. Ordem de resolução (a mais barata primeiro):
/// comandos locais e calculadora (0 tokens) > criação de mídia > cache > IA.
final _noKeyboardMode = KeyboardMode();

class ConsolePanel extends StatefulWidget {
  const ConsolePanel({
    super.key,
    required this.brain,
    required this.router,
    required this.settings,
    required this.voiceStatus,
    required this.onOpenUrl,
    required this.onOpenHub,
    required this.onLaunchApp,
    required this.onInstallApp,
    required this.calc,
    required this.gh,
    required this.sb,
    required this.drive,
    required this.media,
    required this.kit,
    required this.voice,
    required this.tts,
    this.tasks,
    this.keyboard,
  });
  final NotiaBrain brain;
  final AiRouter router;
  final SettingsStore settings;
  final ValueNotifier<String> voiceStatus;
  final void Function(String url) onOpenUrl;
  final void Function(String category, String prompt) onOpenHub;
  final Future<String?> Function(String name) onLaunchApp;
  final void Function(String name) onInstallApp;
  final HybridCalculatorService calc;
  final GitHubSyncService gh;
  final SupabaseSyncService sb;
  final DriveBackupService drive;
  final MediaService media;
  final DeviceKit kit;

  /// Modo do teclado (físico/virtual). Em modo físico o campo não abre o teclado da tela.
  final KeyboardMode? keyboard;
  final VoiceService voice;
  final TtsService tts;

  /// Barra de tarefas da IA (opcional).
  final AiTaskService? tasks;

  @override
  State<ConsolePanel> createState() => ConsolePanelState();
}

class ConsolePanelState extends State<ConsolePanel> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[
    _Msg(
        'Notia pronto. Peça "crie uma música...", "gere uma imagem...", faça contas com =, '
        'diga "abrir <app>" ou "instalar <app>", ou use @gemini, /nota, /lembrar, gh:, sb:, drive:. '
        'Digite "ajuda" para ver o que o Notia faz com o aparelho (agente de apps, notificações, câmera...).',
        color: N.dim),
  ];
  final _player = AudioPlayer();
  bool _listening = false;
  bool _busy = false;

  void _setBusy(bool v, [String title = 'IA pensando…']) {
    if (mounted) setState(() => _busy = v);
    final t = widget.tasks;
    if (t == null) return;
    if (v) {
      t.upsert('console', title);
    } else {
      t.finish('console');
    }
  }
  Timer? _clipTimer;
  String _lastClip = '';
  String? _clipUrl;

  static final _urlRe = RegExp(r'https?://\S+');

  late final DeviceCommands _dev = DeviceCommands(
    kit: widget.kit,
    router: widget.router,
    brain: widget.brain,
    settings: widget.settings,
    say: (t, {Color color = N.dim}) => say(t, color: color),
    speak: speak,
    launch: widget.onLaunchApp,
    openImage: showImage,
    openUrl: widget.onOpenUrl,
  );

  @override
  void initState() {
    super.initState();
    _clipTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkClipboard());
    _announceInbox();
  }

  Future<void> _announceInbox() async {
    final items = await widget.brain.vault.inboxItems();
    if (items.isNotEmpty && mounted) {
      _add(_Msg(
          'Inbox do Vault: ${items.length} pedido(s) deixado(s) por um agente (${items.take(3).join(', ')}).',
          color: N.amber));
    }
  }

  @override
  void dispose() {
    _clipTimer?.cancel();
    widget.voice.stop();
    widget.tts.stop();
    _player.dispose();
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- API usada pela barra inferior e pelo shell ----------
  void insertText(String s) {
    final sel = _ctrl.selection;
    final t = _ctrl.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _ctrl.value = TextEditingValue(
      text: t.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
    _focus.requestFocus();
  }

  void clearInput() {
    _ctrl.clear();
    _focus.unfocus();
    if (_listening) _stopListening();
  }

  void showKeyboard() {
    _focus.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  void say(String text, {Color color = N.dim}) => _add(_Msg(text, color: color));

  void showImage(String path) => _add(_Msg('', mediaPath: path, mediaKind: 'image'));

  void speak(String text) {
    if (widget.settings.speakReplies) widget.tts.speak(text);
  }

  Future<void> ask(String text) => _submit(text);

  // ---------- Compartilhar para o Notia ----------
  Future<void> handleShared(Map<String, dynamic> m) async {
    if (m['kind'] == 'image') {
      say('Imagem recebida. Lendo o texto…', color: N.dim);
      final r = await widget.kit.ocr.scanFile(m['path'] as String);
      if (r == null) {
        say(widget.kit.ocr.lastError, color: N.red);
      } else {
        await _dev.saveScan(r.text, r.path);
      }
      return;
    }
    final text = ((m['text'] as String?) ?? '').trim();
    if (text.isEmpty || !mounted) return;
    final url = _urlRe.firstMatch(text)?.group(0);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text('Recebido para o Notia', style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: Text(text.length > 240 ? '${text.substring(0, 240)}…' : text, style: N.t(c: N.dim)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'nota'),
              child: Text('SALVAR NOTA', style: N.t(c: N.cyan))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'resumir'),
              child: Text('RESUMIR (IA)', style: N.t(c: N.cyan))),
          if (url != null)
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'abrir'),
                child: Text('ABRIR LINK', style: N.t(c: N.cyan))),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('IGNORAR', style: N.t(c: N.dim))),
        ],
      ),
    );
    if (choice == 'nota') {
      final n = DateTime.now();
      final t = 'Compartilhado ${n.day}-${n.month} ${n.hour}h${n.minute.toString().padLeft(2, '0')}';
      final ok = await widget.brain.saveNote(t, text);
      say(ok ? 'Salvei a nota "$t" no Vault.' : 'Salvei a nota "$t" no SQLite (libere "Todos os arquivos" para o Vault).',
          color: N.green);
    } else if (choice == 'resumir') {
      _submit('Resuma em português, em poucas linhas: ${text.length > 3000 ? text.substring(0, 3000) : text}');
    } else if (choice == 'abrir' && url != null) {
      widget.onOpenUrl(url);
    }
  }

  // ---------- Área de transferência ----------
  Future<void> _checkClipboard() async {
    if (!mounted) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final txt = d?.text?.trim() ?? '';
      if (txt.isEmpty || txt == _lastClip) return;
      _lastClip = txt;
      widget.kit.clip.add(txt);
      final m = _urlRe.firstMatch(txt);
      if (m != null && mounted) setState(() => _clipUrl = m.group(0));
    } catch (_) {}
  }

  // ---------- Mensagens ----------
  void _add(_Msg m) {
    if (!mounted) return;
    setState(() => _msgs.add(m));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _submit(String raw) async {
    var text = raw.trim();
    if (_busy && widget.kit.agent.running && RegExp(r'^(parar|pare)\b', caseSensitive: false).hasMatch(text)) {
      widget.kit.agent.stop();
      _ctrl.clear();
      say('Pedi para o agente parar.', color: N.amber);
      return;
    }
    if (text.isEmpty || _busy) return;
    final low = text.toLowerCase();
    for (final w in ['notia', 'assistente']) {
      if (low.startsWith(w)) {
        text = text.substring(w.length).replaceFirst(RegExp(r'^[\s,:.-]+'), '');
        break;
      }
    }
    if (text.isEmpty) return;
    _ctrl.clear();
    _add(_Msg(text, user: true));

    // 1) Comandos locais (0 tokens)
    if (text.startsWith('/nota ')) {
      final body = text.substring(6);
      final i = body.indexOf(':');
      final titulo = i > 0 ? body.substring(0, i).trim() : 'nota';
      final conteudo = i > 0 ? body.substring(i + 1).trim() : body;
      final ok = await widget.brain.saveNote(titulo, conteudo);
      _add(_Msg(
          ok
              ? 'Nota "$titulo" salva no Vault.'
              : 'Nota "$titulo" salva no SQLite. Para gravar no Vault, libere "Todos os arquivos" em CONFIG.',
          color: N.green));
      return;
    }
    if (text.startsWith('/lembrar ')) {
      final body = text.substring(9);
      final i = body.indexOf('=');
      if (i <= 0) {
        _add(_Msg('Use: /lembrar chave=valor', color: N.amber));
        return;
      }
      final ok = await widget.brain
          .remember(body.substring(0, i).trim(), body.substring(i + 1).trim());
      _add(_Msg(
          ok
              ? 'Memorizado (SQLite + Vault).'
              : 'Memorizado no SQLite. Libere "Todos os arquivos" em CONFIG para gravar no Vault.',
          color: N.green));
      return;
    }
    if (widget.calc.isCalc(text)) {
      try {
        final r = await widget.calc.evaluate(text);
        _add(_Msg(r.text, badge: '[calc native: 0 tokens]', color: N.green));
        speak(r.text.replaceFirst('= ', ''));
      } catch (e) {
        _add(_Msg('Não consegui calcular: ${_clean(e)}', color: N.red));
      }
      return;
    }
    final lowCmd = text.toLowerCase();
    if (lowCmd.startsWith('gh:')) return _handleGh(text.substring(3).trim());
    if (lowCmd.startsWith('sb:')) return _handleSb(text.substring(3).trim());
    if (lowCmd.startsWith('drive:')) return _handleDrive(text.substring(6).trim());

    // Recursos do aparelho: agente de apps, notificações, contatos, câmera, rotinas...
    _setBusy(true, 'Executando comando');
    try {
      if (await _dev.handle(text)) return;
    } finally {
      _setBusy(false);
    }

    // Abrir ou instalar apps (Play Store): regras locais, 0 tokens
    final launch = RegExp(r'^(abra|abrir|abre|inicie|iniciar)\s+(?:o\s+|a\s+|os\s+|as\s+)?(.+)$',
            caseSensitive: false)
        .firstMatch(text);
    if (launch != null && launch.group(2)!.split(' ').length <= 4) {
      final wanted = launch.group(2)!.trim();
      final opened = await widget.onLaunchApp(wanted);
      _add(_Msg(
          opened != null
              ? 'Abrindo $opened.'
              : 'Não achei "$wanted" instalado. Diga "instalar $wanted" para buscar na Play Store.',
          color: opened != null ? N.green : N.amber));
      return;
    }
    final install = RegExp(r'^(instale|instalar|baixe|baixar)\s+(?:o\s+|a\s+)?(.+)$',
            caseSensitive: false)
        .firstMatch(text);
    if (install != null && install.group(2)!.split(' ').length <= 4) {
      final wanted = install.group(2)!.trim();
      widget.onInstallApp(wanted);
      _add(_Msg(
          'Abri a Play Store na busca por "$wanted". Toque em Instalar; o app entra na dock sozinho.',
          color: N.green));
      return;
    }

    // 2) Criação de mídia: reconhecida localmente, sem gastar tokens
    final intent = IntentRouter.detect(text);
    if (intent.kind != IntentKind.none) {
      await _handleMedia(intent);
      return;
    }

    // 3) IA: @provedor escolhe a IA; senão o roteador decide
    String? providerId;
    var prompt = text;
    final at = RegExp(r'^@(\S+)\s+(.+)$', dotAll: true).firstMatch(text);
    if (at != null) {
      providerId = at.group(1)!.toLowerCase();
      prompt = at.group(2)!;
    }
    final force = prompt.startsWith('/esp ');
    if (force) prompt = prompt.substring(5);

    _setBusy(true, 'IA pensando…');
    try {
      final r = (providerId == null && !force && widget.calc.needsAi(prompt))
          ? await widget.calc.solveWithAi(prompt)
          : await widget.router.ask(prompt, forceSpecialist: force, providerId: providerId);
      _add(_Msg(r.text, badge: r.badge, color: N.green));
      speak(r.text);
    } catch (e) {
      _add(_Msg('Falha: ${_clean(e)}', color: N.red));
    } finally {
      _setBusy(false);
    }
  }

  // ---------- Mídia por IA ----------
  Future<void> _play(String path) async {
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (_) {}
  }

  Future<void> _handleMedia(Intent it) async {
    if (it.kind == IntentKind.video) {
      widget.onOpenHub('video', it.prompt);
      _add(_Msg(
          'Ainda não há API de vídeo gratuita e estável. Copiei seu pedido e abri as ferramentas de vídeo no Hub: cole lá.',
          color: N.amber));
      return;
    }
    final music = it.kind == IntentKind.music;
    _setBusy(true, music ? 'Compondo música' : 'Gerando imagem');
    _add(_Msg(music ? 'Compondo… pode levar até 1 minuto.' : 'Gerando a imagem…', color: N.dim));
    try {
      final r = music ? await widget.media.music(it.prompt) : await widget.media.image(it.prompt);
      await widget.brain.logEvent('midia', '${r.kind}: ${it.prompt}');
      _add(_Msg(music ? 'Pronto, sua música está tocando.' : 'Pronto, sua imagem.',
          badge: music ? '[musicgen · salvo em Midia/Musicas]' : '[pollinations · salvo em Midia/Imagens]',
          color: N.green,
          mediaPath: r.path,
          mediaKind: r.kind));
      if (music) _play(r.path);
      speak(music ? 'Pronto, sua música está tocando.' : 'Pronto, sua imagem.');
    } catch (e) {
      _add(_Msg('Não consegui criar agora: ${_clean(e)}.', color: N.red));
      if (music) {
        widget.onOpenHub('musica', it.prompt);
        _add(_Msg('Copiei o pedido e abri as ferramentas de música no Hub (Suno, Udio).',
            color: N.amber));
      }
    } finally {
      _setBusy(false);
    }
  }

  // ---------- GitHub, Supabase e Drive (com confirmação antes de enviar/sobrescrever) ----------
  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text('Confirmar', style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: Text(msg, style: N.t()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('NÃO', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('SIM', style: N.t(c: N.cyan, w: FontWeight.w700))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _handleGh(String cmd) async {
    const usage =
        'Use: gh: commit [dono/repo] slug-da-nota   ou   gh: dispatch [dono/repo] evento';
    final parts = cmd.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) {
      _add(_Msg(usage, color: N.amber));
      return;
    }
    final action = parts.first.toLowerCase();
    var rest = parts.skip(1).toList();
    var repo = widget.settings.ghRepo;
    if (rest.first.contains('/')) {
      repo = rest.first;
      rest = rest.skip(1).toList();
    }
    if (repo.isEmpty || rest.isEmpty) {
      _add(_Msg('Defina o repositório padrão em CONFIG ou informe dono/repo. $usage',
          color: N.amber));
      return;
    }
    if (action == 'commit') {
      final slug = rest.first;
      final notes = await widget.brain.notes();
      final row = notes.where((n) => n['chave'] == 'nota:$slug').toList();
      if (row.isEmpty) {
        _add(_Msg('Não achei a nota "$slug".', color: N.red));
        return;
      }
      final v = (row.first['valor'] as String?) ?? '';
      final i = v.indexOf('\n');
      final title = i > 0 ? v.substring(0, i) : slug;
      final body = i > 0 ? v.substring(i + 1) : '';
      if (!await _confirm('Enviar a nota "$slug" para $repo em notas/$slug.md?')) {
        _add(_Msg('Cancelado.', color: N.dim));
        return;
      }
      final ok = await widget.gh
          .commitNota(repo, 'notas/$slug.md', '# $title\n\n$body\n', 'Notia: atualiza $slug');
      await widget.brain.logEvent('github_commit', '$repo notas/$slug.md');
      _add(_Msg(ok ? 'Commit feito em $repo (notas/$slug.md).' : 'Falhou: ${widget.gh.lastError}',
          color: ok ? N.green : N.red));
    } else if (action == 'dispatch') {
      final evento = rest.first;
      if (!await _confirm('Disparar o evento "$evento" em $repo?')) {
        _add(_Msg('Cancelado.', color: N.dim));
        return;
      }
      final ok = await widget.gh.triggerWorkflow(repo, evento, {'origem': 'notia'});
      await widget.brain.logEvent('github_dispatch', '$repo $evento');
      _add(_Msg(ok ? 'Evento "$evento" disparado em $repo.' : 'Falhou: ${widget.gh.lastError}',
          color: ok ? N.green : N.red));
    } else {
      _add(_Msg(usage, color: N.amber));
    }
  }

  Future<void> _handleSb(String cmd) async {
    final action = cmd.toLowerCase().trim();
    if (action == 'backup') {
      final ok = await widget.sb.backup();
      await widget.brain.logEvent('supabase_backup', ok ? 'ok' : 'falhou');
      _add(_Msg(ok ? 'Backup enviado ao Supabase.' : 'Falhou: ${widget.sb.lastError}',
          color: ok ? N.green : N.red));
    } else if (action == 'restore') {
      if (!await _confirm(
          'Restaurar vai substituir memórias, histórico e variáveis deste tablet pelo backup da nuvem. Continuar?')) {
        _add(_Msg('Cancelado.', color: N.dim));
        return;
      }
      final ok = await widget.sb.restore();
      _add(_Msg(ok ? 'Backup restaurado.' : 'Falhou: ${widget.sb.lastError}',
          color: ok ? N.green : N.red));
    } else if (action == 'status') {
      _add(_Msg(
          'Supabase: ${widget.sb.status.value}${widget.sb.lastError.isEmpty ? '' : ' · ${widget.sb.lastError}'}',
          color: N.dim));
    } else {
      _add(_Msg('Use: sb: backup | sb: restore | sb: status', color: N.amber));
    }
  }

  Future<void> _handleDrive(String cmd) async {
    final action = cmd.toLowerCase().trim();
    if (action == 'backup') {
      _add(_Msg('Enviando ao Drive…', color: N.dim));
      final r = await widget.drive.backup();
      _add(_Msg(r ?? 'Falhou: ${widget.drive.lastError}', color: r != null ? N.green : N.red));
    } else if (action == 'restore') {
      if (!await _confirm(
          'Restaurar baixa o backup do Drive, sobrescreve arquivos do Vault e substitui memórias, histórico e variáveis deste tablet. Continuar?')) {
        _add(_Msg('Cancelado.', color: N.dim));
        return;
      }
      final r = await widget.drive.restore();
      _add(_Msg(r ?? 'Falhou: ${widget.drive.lastError}', color: r != null ? N.green : N.red));
    } else if (action == 'status') {
      _add(_Msg(
          'Drive: ${widget.drive.status.value}${widget.drive.lastError.isEmpty ? '' : ' · ${widget.drive.lastError}'}',
          color: N.dim));
    } else {
      _add(_Msg('Use: drive: backup | drive: restore | drive: status', color: N.amber));
    }
  }

  // ---------- Voz ----------
  int _micTries = 0;

  Future<void> toggleMic() async {
    await widget.tts.stop(); // não ouve a própria voz
    if (_listening) {
      _micTries = 99; // toque do usuário: não reabrir sozinho
      await _stopListening();
      return;
    }
    _micTries = 0;
    await _startMic();
  }

  /// Abre o microfone. Se o Android encerrar sem ouvir nada (silêncio inicial), reabre
  /// até 3 vezes, para dar tempo de começar a falar.
  Future<void> _startMic() async {
    var heard = false;
    if (mounted) setState(() => _listening = true);
    widget.voiceStatus.value = 'OUVINDO';
    final ok = await widget.voice.listen(
      owner: 'console',
      pauseFor: const Duration(seconds: 5),
      onResult: (t, fin) {
        if (t.trim().isNotEmpty) heard = true;
        _ctrl.text = t;
        if (fin) {
          _micTries = 99;
          _stopListening();
          _submit(t);
        }
      },
      onEnd: () {
        if (!mounted) return;
        if (!heard && _micTries < 3 && _listening) {
          _micTries++;
          Future<void>.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _listening) _startMic();
          });
          return;
        }
        setState(() => _listening = false);
        widget.voiceStatus.value = 'PRONTA';
      },
    );
    if (!ok) {
      if (mounted) setState(() => _listening = false);
      _add(_Msg('Microfone indisponível. Confira a permissão de áudio.', color: N.red));
      widget.voiceStatus.value = 'INDISPONÍVEL';
    }
  }

  Future<void> _stopListening() async {
    await widget.voice.stop();
    if (mounted) setState(() => _listening = false);
    widget.voiceStatus.value = 'PRONTA';
  }

  // ---------- UI ----------
  Widget _bubble(_Msg m) {
    if (m.user) {
      return Text.rich(TextSpan(children: [
        TextSpan(text: 'você> ', style: N.t(c: N.dim)),
        TextSpan(text: m.text, style: N.t()),
      ]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (m.badge != null) Text(m.badge!, style: N.t(c: N.violet, s: 11)),
        Text(m.text, style: N.t(c: m.color)),
        if (m.mediaKind == 'image' && m.mediaPath != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(m.mediaPath!), height: 170, fit: BoxFit.cover),
            ),
          ),
        if (m.mediaKind == 'music' && m.mediaPath != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              NBtn('TOCAR', accent: true, onTap: () => _play(m.mediaPath!)),
              const SizedBox(width: 8),
              NBtn('PARAR', onTap: () => _player.stop()),
            ]),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length,
            itemBuilder: (c, i) =>
                Padding(padding: const EdgeInsets.only(bottom: 8), child: _bubble(_msgs[i])),
          ),
        ),
        if (_clipUrl != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: N.amber),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Identifiquei um link copiado. Abrir no navegador?',
                      style: N.t(c: N.amber, s: 12)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    final u = _clipUrl!;
                    setState(() => _clipUrl = null);
                    widget.onOpenUrl(u);
                  },
                  child: Text('ABRIR', style: N.t(c: N.cyan, w: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () => setState(() => _clipUrl = null),
                  child: Text('IGNORAR', style: N.t(c: N.dim)),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: N.line2))),
          child: Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.keyboard ?? _noKeyboardMode,
                  builder: (c, _) => TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  keyboardType: (widget.keyboard?.useVirtual ?? true)
                      ? TextInputType.text
                      : TextInputType.none,
                  style: N.t(),
                  cursorColor: N.cyan,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _submit,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: N.field,
                    hintText: _busy ? 'Trabalhando…' : 'Fale ou digite um comando…',
                    hintStyle: N.t(c: N.dim),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: N.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: N.cyan)),
                  ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              NBtn(_listening ? 'OUVINDO' : 'MIC', accent: true, onTap: toggleMic),
            ],
          ),
        ),
      ],
    );
  }
}
