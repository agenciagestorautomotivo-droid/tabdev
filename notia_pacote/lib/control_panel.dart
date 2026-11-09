import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/ai_router.dart';
import 'services/clipboard_history_service.dart';
import 'services/connector_store.dart';
import 'services/google_services.dart';
import 'services/library_store.dart';
import 'services/native_bridge.dart';
import 'services/notia_brain.dart';
import 'services/repo_store.dart';
import 'services/settings_store.dart';
import 'services/supabase_sync_service.dart';
import 'services/system_monitor_service.dart';
import 'services/termux_service.dart';
import 'services/tts_service.dart';
import 'theme.dart';

/// Painel de controle do OpenEXE: IAs, repositórios, conectores, plugins, mods e biblioteca
/// de scripts/prompts num só lugar. Tela cheia; tudo salva na hora.
class ControlPanel extends StatefulWidget {
  const ControlPanel({
    super.key,
    required this.settings,
    required this.router,
    required this.repos,
    required this.library,
    required this.connectors,
    required this.google,
    required this.sb,
    required this.runCommand,
    required this.openConfig,
    required this.onChanged,
    required this.brain,
    required this.clip,
    required this.monitor,
    required this.lockNow,
    required this.termuxService,
    required this.tts,
  });
  final SettingsStore settings;
  final AiRouter router;
  final RepoStore repos;
  final LibraryStore library;
  final ConnectorStore connectors;
  final GoogleAuthService google;
  final SupabaseSyncService sb;
  final Future<void> Function(String command) runCommand;
  final VoidCallback openConfig;
  final VoidCallback onChanged;
  final NotiaBrain brain;
  final ClipboardHistoryService clip;
  final SystemMonitorService monitor;
  final VoidCallback lockNow;
  final TermuxService termuxService;
  final TtsService tts;

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  int _tab = 0;
  final Map<String, String> _test = {}; // resultado dos testes por id
  final Set<String> _busy = {};
  final Map<String, TextEditingController> _c = {};
  List<String>? _mine;
  String _mineMsg = '';
  String _libFilter = 'todos';
  bool _a11y = false, _notif = false;

  SettingsStore get s => widget.settings;

  static const _tabs = [
    ['IAs', Icons.psychology_alt_outlined],
    ['Repositórios', Icons.folder_copy_outlined],
    ['Conectores', Icons.cable_outlined],
    ['Plugins', Icons.extension_outlined],
    ['Mods', Icons.dashboard_customize_outlined],
    ['Scripts e prompts', Icons.terminal_outlined],
    ['Segurança', Icons.shield_outlined],
    ['Otimização', Icons.speed_outlined],
    ['Dev · Termux', Icons.code],
    ['Voz', Icons.record_voice_over_outlined],
  ];

  @override
  void initState() {
    super.initState();
    _status();
    _loadSecOpt();
  }

  Map<String, dynamic> _sec = {};
  Map<String, dynamic> _opt = {};
  Map<String, PermissionStatus> _perms = {};
  int _aiCache = 0, _history = 0;
  TermuxState? _tx;
  String _termOut = '';
  List<String> _projects = [];
  List<Map<String, String>> _sysVoices = [];
  String _ttsNote = '';
  bool _voicesLoaded = false;

  Future<void> _loadSecOpt() async {
    final sec = await NativeBridge.secInfo();
    final opt = await NativeBridge.optInfo();
    final perms = <String, PermissionStatus>{
      'Microfone': await Permission.microphone.status,
      'Contatos': await Permission.contacts.status,
      'Agenda': await Permission.calendar.status,
      'Localização': await Permission.locationWhenInUse.status,
      'Notificações do app': await Permission.notification.status,
    };
    final ac = await widget.brain.countCache();
    final hi = await widget.brain.countHistory();
    final tx = await TermuxService.state();
    if (mounted) {
      setState(() {
        _sec = sec;
        _opt = opt;
        _perms = perms;
        _aiCache = ac;
        _history = hi;
        _tx = tx;
      });
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _status() async {
    final a = await NativeBridge.a11yEnabled();
    final n = await NativeBridge.notifEnabled();
    if (mounted) {
      setState(() {
        _a11y = a;
        _notif = n;
      });
    }
  }

  TextEditingController ctl(String k, [String init = '']) =>
      _c.putIfAbsent(k, () => TextEditingController(text: init));

  void _changed() {
    widget.onChanged();
    if (mounted) setState(() {});
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
  }

  // ---------- peças visuais ----------
  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: N.field,
        labelText: label,
        hintText: hint,
        labelStyle: N.t(c: N.dim, s: 12),
        hintStyle: N.t(c: N.dim, s: 11),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: N.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: N.cyan)),
      );

  Widget _field(String key, String label,
          {String init = '', bool secret = false, String? hint, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctl(key, init),
          obscureText: secret,
          minLines: lines,
          maxLines: lines,
          style: N.t(s: 13),
          decoration: _dec(label, hint: hint),
        ),
      );

  Widget _card({required Widget child, Color? edge}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: N.field,
          border: Border.all(color: edge ?? N.border, width: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      );

  Widget _h(String t, {String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: N.t(c: N.cyan, s: 16, w: FontWeight.w700)),
          if (sub != null) Text(sub, style: N.t(c: N.dim, s: 12)),
        ]),
      );

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            border: Border.all(color: c, width: 0.7), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: N.t(c: c, s: 10, w: FontWeight.w700)),
      );

  Widget _switch(String title, String sub, bool v, Future<void> Function(bool) on) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title, style: N.t(s: 13)),
        subtitle: Text(sub, style: N.t(c: N.dim, s: 11)),
        value: v,
        activeColor: N.cyan,
        onChanged: (x) async {
          await on(x);
          _changed();
        },
      );

  // ---------- IAs ----------
  Future<void> _testAi(String id) async {
    setState(() => _busy.add('ai$id'));
    try {
      final r = await widget.router.ask('responda só: ok (agora ${DateTime.now().millisecondsSinceEpoch})',
          providerId: id);
      _test['ai$id'] = '✓ ${r.text.trim().split('\n').first}';
    } catch (e) {
      _test['ai$id'] = '✗ ${e.toString().replaceFirst('Exception: ', '')}';
    }
    if (mounted) setState(() => _busy.remove('ai$id'));
  }

  Widget _builtinAi(String id, String name, String keyHelp, String key, Future<void> Function(String) setKey,
      {String? model, Future<void> Function(String)? setModel}) {
    final off = s.aiDisabled.contains(id);
    final ok = key.isNotEmpty;
    final res = _test['ai$id'];
    return _card(
      edge: ok && !off ? N.cyan.withOpacity(0.5) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: N.t(w: FontWeight.w700, s: 14))),
          _pill(!ok ? 'SEM CHAVE' : (off ? 'DESLIGADA' : 'ATIVA'), !ok ? N.amber : (off ? N.dim : N.green)),
          const SizedBox(width: 8),
          Switch(
            value: !off,
            activeColor: N.cyan,
            onChanged: (v) async {
              final l = [...s.aiDisabled];
              v ? l.remove(id) : l.add(id);
              await s.setAiDisabled(l);
              _changed();
            },
          ),
        ]),
        Text(keyHelp, style: N.t(c: N.dim, s: 11)),
        const SizedBox(height: 8),
        _field('k$id', 'Chave', init: key, secret: true),
        if (model != null) _field('m$id', 'Modelo', init: model),
        Row(children: [
          NBtn('Salvar', accent: true, onTap: () async {
            await setKey(ctl('k$id').text);
            if (setModel != null) await setModel(ctl('m$id').text);
            _snack('$name salvo.');
            _changed();
          }),
          const SizedBox(width: 8),
          NBtn(_busy.contains('ai$id') ? 'Testando…' : 'Testar',
              onTap: _busy.contains('ai$id') ? null : () => _testAi(id)),
          const SizedBox(width: 10),
          if (res != null)
            Expanded(
                child: Text(res,
                    style: N.t(c: res.startsWith('✓') ? N.green : N.red, s: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
        ]),
      ]),
    );
  }

  Widget _aiTab() {
    final customs = s.customProviders;
    final names = <String>['auto', 'gemini', 'openrouter', 'groq', ...customs.map((e) => (e['name'] ?? '').toLowerCase())];
    final spec = names.contains(s.specialist) ? s.specialist : 'auto';
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('IAs', sub: 'Todas gratuitas por padrão. O OpenEXE tenta uma por vez e passa para a próxima se uma falhar.'),
      _card(
        child: Row(children: [
          Expanded(
              child: Text('Quem atende pedidos complexos (roteiros, análises)',
                  style: N.t(s: 13))),
          DropdownButton<String>(
            value: spec,
            dropdownColor: N.field,
            underline: const SizedBox(),
            style: N.t(s: 13),
            items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
            onChanged: (v) async {
              await s.setSpecialist(v ?? 'auto');
              _changed();
            },
          ),
        ]),
      ),
      _builtinAi('groq', 'Groq', 'Rápida, grátis. Pega a chave em console.groq.com.', s.groqKey, s.setGroqKey,
          model: s.groqModel, setModel: s.setGroqModel),
      _builtinAi('gemini', 'Google Gemini', 'Grátis com limite. Chave em aistudio.google.com.', s.geminiKey,
          s.setGeminiKey,
          model: s.geminiModel, setModel: s.setGeminiModel),
      _builtinAi('openrouter', 'OpenRouter', 'Modelos ":free". Chave em openrouter.ai.', s.openrouterKey,
          s.setOpenrouterKey,
          model: s.openrouterModel, setModel: s.setOpenrouterModel),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: Text('Provedores próprios (formato OpenAI)', style: N.t(c: N.cyan, w: FontWeight.w700))),
        NBtn('+ Novo', accent: true, onTap: () => _editProvider(null)),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in const [
          ['DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'],
          ['Mistral', 'https://api.mistral.ai/v1', 'mistral-small-latest'],
          ['Together', 'https://api.together.xyz/v1', 'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free'],
          ['Ollama local', 'http://192.168.0.10:11434/v1', 'llama3.2'],
        ])
          NBtn(p[0], onTap: () => _editProvider(null, preset: p)),
      ]),
      const SizedBox(height: 8),
      if (customs.isEmpty) Text('Nenhum provedor próprio ainda.', style: N.t(c: N.dim, s: 12)),
      for (var i = 0; i < customs.length; i++) _customCard(i, customs),
    ]);
  }

  Widget _customCard(int i, List<Map<String, String>> customs) {
    final c = customs[i];
    final id = (c['name'] ?? '').toLowerCase();
    final off = s.aiDisabled.contains(id);
    final res = _test['ai$id'];
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${c['name']}  ·  ${c['model']}', style: N.t(w: FontWeight.w700))),
          Switch(
            value: !off,
            activeColor: N.cyan,
            onChanged: (v) async {
              final l = [...s.aiDisabled];
              v ? l.remove(id) : l.add(id);
              await s.setAiDisabled(l);
              _changed();
            },
          ),
        ]),
        Text(c['baseUrl'] ?? '', style: N.t(c: N.dim, s: 11)),
        const SizedBox(height: 8),
        Row(children: [
          NBtn('Editar', onTap: () => _editProvider(i)),
          const SizedBox(width: 8),
          NBtn(_busy.contains('ai$id') ? 'Testando…' : 'Testar',
              onTap: _busy.contains('ai$id') ? null : () => _testAi(id)),
          const SizedBox(width: 8),
          NBtn('Remover', onTap: () async {
            final l = [...customs]..removeAt(i);
            await s.setCustomProviders(l);
            _changed();
          }),
          const SizedBox(width: 10),
          if (res != null)
            Expanded(
                child: Text(res,
                    style: N.t(c: res.startsWith('✓') ? N.green : N.red, s: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
        ]),
      ]),
    );
  }

  Future<void> _editProvider(int? i, {List<String>? preset}) async {
    final list = [...s.customProviders];
    final cur = i == null ? <String, String>{} : list[i];
    final n = TextEditingController(text: cur['name'] ?? preset?[0] ?? '');
    final u = TextEditingController(text: cur['baseUrl'] ?? preset?[1] ?? '');
    final m = TextEditingController(text: cur['model'] ?? preset?[2] ?? '');
    final k = TextEditingController(text: cur['key'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text(i == null ? 'Novo provedor' : 'Editar provedor',
            style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, style: N.t(), decoration: _dec('Nome')),
            const SizedBox(height: 8),
            TextField(controller: u, style: N.t(), decoration: _dec('URL base (…/v1)')),
            const SizedBox(height: 8),
            TextField(controller: m, style: N.t(), decoration: _dec('Modelo')),
            const SizedBox(height: 8),
            TextField(controller: k, obscureText: true, style: N.t(), decoration: _dec('Chave (vazia no Ollama)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('CANCELAR', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('SALVAR', style: N.t(c: N.cyan, w: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || n.text.trim().isEmpty || u.text.trim().isEmpty || m.text.trim().isEmpty) return;
    final item = {
      'name': n.text.trim(),
      'baseUrl': u.text.trim(),
      'model': m.text.trim(),
      'key': k.text.trim()
    };
    if (i == null) {
      list.add(item);
    } else {
      list[i] = item;
    }
    await s.setCustomProviders(list);
    _changed();
  }

  // ---------- Repositórios ----------
  Widget _repoTab() {
    final all = widget.repos.all;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Repositórios', sub: 'Aparecem na aba REPOSITÓRIOS do Hub. A estrela é o padrão do comando gh:.'),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _field('ghtok', 'Token do GitHub (repositórios privados e releases)',
              init: s.ghToken, secret: true),
          Row(children: [
            NBtn('Salvar token', accent: true, onTap: () async {
              await s.setGhToken(ctl('ghtok').text);
              _snack('Token salvo.');
              _changed();
            }),
            const SizedBox(width: 8),
            NBtn('Buscar meus repositórios', onTap: () async {
              setState(() => _mineMsg = 'Buscando…');
              final r = await widget.repos.fetchMine();
              setState(() {
                _mine = r;
                _mineMsg = r == null ? 'Falhou. Confira o token.' : '${r.length} repositórios.';
              });
            }),
            const SizedBox(width: 10),
            Text(_mineMsg, style: N.t(c: N.dim, s: 11)),
          ]),
        ]),
      ),
      _card(
        child: Row(children: [
          Expanded(child: TextField(controller: ctl('repoadd'), style: N.t(), decoration: _dec('dono/repo ou URL do GitHub'))),
          const SizedBox(width: 8),
          NBtn('Adicionar', accent: true, onTap: () async {
            final ok = await widget.repos.add(ctl('repoadd').text);
            if (ok) ctl('repoadd').clear();
            _snack(ok ? 'Repositório adicionado.' : 'Formato inválido. Use dono/repo.');
            _changed();
          }),
        ]),
      ),
      for (final r in all)
        _card(
          child: Row(children: [
            IconButton(
              icon: Icon(widget.repos.defaultRepo == r ? Icons.star : Icons.star_border,
                  color: N.amber, size: 20),
              tooltip: 'Padrão',
              onPressed: () async {
                await widget.repos.setDefault(r);
                _changed();
              },
            ),
            Expanded(child: Text(r, style: N.t(s: 13))),
            NBtn('Copiar URL', onTap: () {
              Clipboard.setData(ClipboardData(text: widget.repos.url(r)));
              _snack('URL copiada.');
            }),
            const SizedBox(width: 8),
            NBtn('Remover', onTap: () async {
              await widget.repos.remove(r);
              _changed();
            }),
          ]),
        ),
      if (_mine != null) ...[
        const SizedBox(height: 8),
        Text('Da sua conta', style: N.t(c: N.cyan, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in _mine!.where((e) => !all.contains(e)))
            NBtn('+ $r', onTap: () async {
              await widget.repos.add(r);
              _changed();
            }),
        ]),
      ],
    ]);
  }

  // ---------- Conectores ----------
  Widget _statusRow(String name, String sub, bool on, {Widget? action}) => _card(
        child: Row(children: [
          Icon(on ? Icons.check_circle : Icons.circle_outlined, color: on ? N.green : N.dim, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: N.t(w: FontWeight.w700, s: 13)),
              Text(sub, style: N.t(c: N.dim, s: 11)),
            ]),
          ),
          if (action != null) action,
        ]),
      );

  Widget _connTab() {
    final cs = widget.connectors.all;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Conectores', sub: 'Serviços ligados ao OpenEXE e webhooks seus (n8n, Make, Zapier, APIs).'),
      _statusRow('Google (Drive e Agenda)',
          widget.google.signedIn ? 'Conectado como ${widget.google.email}' : 'Não conectado', widget.google.signedIn,
          action: widget.google.signedIn
              ? null
              : NBtn('Entrar', accent: true, onTap: () async {
                  await widget.google.signIn();
                  _changed();
                })),
      _statusRow('GitHub', s.ghToken.isEmpty ? 'Sem token (aba Repositórios)' : 'Token salvo', s.ghToken.isNotEmpty,
          action: NBtn('Repositórios', onTap: () => setState(() => _tab = 1))),
      _statusRow('Supabase (opcional)', widget.sb.configured ? 'Configurado' : 'Não configurado', widget.sb.configured,
          action: NBtn('Configurar', onTap: widget.openConfig)),
      _statusRow('Controle de apps (acessibilidade)', _a11y ? 'Ativo' : 'Desligado', _a11y,
          action: NBtn('Ajustes', onTap: () => NativeBridge.openSettings('accessibility'))),
      _statusRow('Ler notificações', _notif ? 'Ativo' : 'Desligado', _notif,
          action: NBtn('Ajustes', onTap: () => NativeBridge.openSettings('notifications'))),
      Align(alignment: Alignment.centerLeft, child: NBtn('Atualizar status', onTap: _status)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Text('Conectores próprios (webhook)', style: N.t(c: N.cyan, w: FontWeight.w700))),
        NBtn('+ Novo', accent: true, onTap: () => _editConnector(null)),
      ]),
      const SizedBox(height: 4),
      Text('No console: conector nome: texto. O OpenEXE faz POST {"text","source"} e mostra a resposta.',
          style: N.t(c: N.dim, s: 11)),
      const SizedBox(height: 8),
      if (cs.isEmpty) Text('Nenhum conector próprio.', style: N.t(c: N.dim, s: 12)),
      for (final c in cs)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: N.t(w: FontWeight.w700)),
            Text(c.url, style: N.t(c: N.dim, s: 11), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              NBtn('Editar', onTap: () => _editConnector(c)),
              const SizedBox(width: 8),
              NBtn(_busy.contains('cn${c.name}') ? 'Enviando…' : 'Testar', onTap: () async {
                setState(() => _busy.add('cn${c.name}'));
                final r = await widget.connectors.call(c, 'teste do OpenEXE');
                _test['cn${c.name}'] = r;
                if (mounted) setState(() => _busy.remove('cn${c.name}'));
              }),
              const SizedBox(width: 8),
              NBtn('Remover', onTap: () async {
                await widget.connectors.remove(c.name);
                _changed();
              }),
            ]),
            if (_test['cn${c.name}'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_test['cn${c.name}']!, style: N.t(c: N.text, s: 11), maxLines: 4, overflow: TextOverflow.ellipsis),
              ),
          ]),
        ),
    ]);
  }

  Future<void> _editConnector(Connector? c) async {
    final n = TextEditingController(text: c?.name ?? '');
    final u = TextEditingController(text: c?.url ?? '');
    final a = TextEditingController(text: c?.auth ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text(c == null ? 'Novo conector' : 'Editar conector', style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, style: N.t(), decoration: _dec('Nome (sem espaços de preferência)')),
            const SizedBox(height: 8),
            TextField(controller: u, style: N.t(), decoration: _dec('URL do webhook')),
            const SizedBox(height: 8),
            TextField(
                controller: a,
                obscureText: true,
                style: N.t(),
                decoration: _dec('Authorization (opcional, ex.: Bearer xxx)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('CANCELAR', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('SALVAR', style: N.t(c: N.cyan, w: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || n.text.trim().isEmpty || u.text.trim().isEmpty) return;
    await widget.connectors
        .upsert(Connector(n.text.trim(), u.text.trim(), auth: a.text.trim()), oldName: c?.name);
    _changed();
  }

  // ---------- Plugins ----------
  Widget _pluginTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Plugins', sub: 'Módulos internos do OpenEXE. Ligue só o que usa para poupar bateria.'),
      _card(
        child: Column(children: [
          _switch('Palavra de ativação', 'Escuta "ei exe, …" com o app aberto. Gasta bateria.', s.wakeOn, (v) async {
            if (v) {
              final r = await Permission.microphone.request();
              if (!r.isGranted) {
                _snack('Permita o microfone para o OpenEXE.');
                return;
              }
            }
            await s.setWakeOn(v);
          }),
          _switch('Modo segundo plano', 'Notificação fixa "OpenEXE ativo" para o Android não encerrar o app.',
              s.keepAlive, s.setKeepAlive),
          _switch('Tela de bloqueio do OpenEXE', 'Camada extra com biometria/PIN do aparelho.', s.osLock, s.setOsLock),
          _switch('Bloquear o Vault do Notia', 'Pede biometria ao voltar depois de 5 min.', s.lockVault, s.setLockVault),
          _switch('Proteger a CONFIG', 'Pede biometria para abrir as configurações.', s.lockConfig, s.setLockConfig),
          _switch('Backup automático no Drive', 'Só no Wi-Fi e com bateria boa.', s.driveAuto, s.setDriveAuto),
          _switch('Atualização automática', 'Baixa o APK novo no Wi-Fi; a instalação pede um toque.',
              s.autoUpdate, s.setAutoUpdate),
        ]),
      ),
      Text('Plugins de terceiros ainda não existem: o que roda aqui são os módulos do próprio OpenEXE. '
          'Para estender, use Scripts e prompts e Conectores.',
          style: N.t(c: N.dim, s: 11)),
    ]);
  }

  // ---------- Mods (layout) ----------
  static const _modNames = ['Console de IA', 'Hub de IAs', 'Cérebro (NotIA)', 'Dock e navegador', 'Apps instalados'];
  static const _posNames = ['Esquerda · cima', 'Esquerda · baixo', 'Direita · 1ª sanfona', 'Direita · 2ª sanfona', 'Direita · 3ª sanfona'];

  Widget _modTab() {
    final slots = [...s.slots5];
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Mods', sub: 'Monte a tela: qual módulo fica em cada lugar e o que abre por padrão. Vale ao fechar o painel.'),
      _card(
        child: Column(children: [
          for (var p = 0; p < 5; p++)
            Row(children: [
              Expanded(child: Text(_posNames[p], style: N.t(s: 13))),
              DropdownButton<int>(
                value: slots[p],
                dropdownColor: N.field,
                underline: const SizedBox(),
                style: N.t(s: 13),
                items: [for (var m = 0; m < 5; m++) DropdownMenuItem(value: m, child: Text(_modNames[m]))],
                onChanged: (m) async {
                  if (m == null) return;
                  final other = slots.indexOf(m);
                  slots[other] = slots[p];
                  slots[p] = m;
                  await s.setSlots5(slots);
                  _changed();
                },
              ),
            ]),
        ]),
      ),
      _card(
        child: Row(children: [
          Expanded(child: Text('Abre por padrão na sanfona (direita)', style: N.t(s: 13))),
          Builder(builder: (_) {
            final right = slots.sublist(2);
            final cur = right.contains(s.openRight) ? s.openRight : right.first;
            return DropdownButton<int>(
              value: cur,
              dropdownColor: N.field,
              underline: const SizedBox(),
              style: N.t(s: 13),
              items: [for (final m in right) DropdownMenuItem(value: m, child: Text(_modNames[m]))],
              onChanged: (m) async {
                await s.setOpenRight(m ?? 3);
                _changed();
              },
            );
          }),
        ]),
      ),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Largura da coluna esquerda: ${(s.col5 * 100).round()}%', style: N.t(s: 13)),
          Slider(
            value: s.col5,
            min: 0.3,
            max: 0.7,
            activeColor: N.cyan,
            onChanged: (v) async {
              await s.setSplits5(v, s.left5, s.rightA5, s.rightB5);
              _changed();
            },
          ),
          Text('Altura do módulo de cima (esquerda): ${(s.left5 * 100).round()}%', style: N.t(s: 13)),
          Slider(
            value: s.left5,
            min: 0.25,
            max: 0.75,
            activeColor: N.cyan,
            onChanged: (v) async {
              await s.setSplits5(s.col5, v, s.rightA5, s.rightB5);
              _changed();
            },
          ),
        ]),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: NBtn('Restaurar layout padrão', onTap: () async {
          await s.setSlots5(const [0, 2, 1, 4, 3]);
          await s.setSplits5(0.46, 0.56, 0.36, 0.30);
          await s.setOpenRight(3);
          _changed();
        }),
      ),
    ]);
  }

  // ---------- Scripts e prompts ----------
  Widget _libTab() {
    final items = widget.library.all
        .where((e) => _libFilter == 'todos' || e.kind == (_libFilter == 'scripts' ? 'script' : 'prompt'))
        .toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Scripts e prompts',
          sub: 'Prompt = texto enviado ao console. Script = um comando por linha, rodando em sequência (# comenta).'),
      Row(children: [
        for (final f in const ['todos', 'prompts', 'scripts'])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: NBtn(f, accent: _libFilter == f, onTap: () => setState(() => _libFilter = f)),
          ),
        const Spacer(),
        NBtn('+ Prompt', accent: true, onTap: () => _editLib(null, 'prompt')),
        const SizedBox(width: 6),
        NBtn('+ Script', accent: true, onTap: () => _editLib(null, 'script')),
      ]),
      const SizedBox(height: 10),
      if (items.isEmpty) Text('Nada aqui ainda.', style: N.t(c: N.dim, s: 12)),
      for (final it in items)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _pill(it.isScript ? 'SCRIPT' : 'PROMPT', it.isScript ? N.amber : N.violet),
              const SizedBox(width: 8),
              Expanded(child: Text(it.name, style: N.t(w: FontWeight.w700))),
            ]),
            const SizedBox(height: 6),
            Text(it.body, style: N.t(c: N.dim, s: 12), maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              NBtn(_busy.contains('lib${it.id}') ? 'Rodando…' : (it.isScript ? 'Executar' : 'Enviar ao console'),
                  accent: true, onTap: () async {
                if (_busy.contains('lib${it.id}')) return;
                setState(() => _busy.add('lib${it.id}'));
                await widget.library.runItem(it);
                if (mounted) setState(() => _busy.remove('lib${it.id}'));
              }),
              NBtn('Copiar', onTap: () {
                Clipboard.setData(ClipboardData(text: it.body));
                _snack('Copiado.');
              }),
              NBtn('Editar', onTap: () => _editLib(it, it.kind)),
              NBtn('Apagar', onTap: () async {
                await widget.library.remove(it.id);
                _changed();
              }),
            ]),
          ]),
        ),
    ]);
  }

  Future<void> _editLib(LibItem? it, String kind) async {
    final n = TextEditingController(text: it?.name ?? '');
    final b = TextEditingController(text: it?.body ?? '');
    var k = kind;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          title: Text(it == null ? 'Novo $k' : 'Editar $k', style: N.t(c: N.cyan, w: FontWeight.w700)),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                NBtn('Prompt', accent: k == 'prompt', onTap: () => setD(() => k = 'prompt')),
                const SizedBox(width: 6),
                NBtn('Script', accent: k == 'script', onTap: () => setD(() => k = 'script')),
              ]),
              const SizedBox(height: 8),
              TextField(controller: n, style: N.t(), decoration: _dec('Nome')),
              const SizedBox(height: 8),
              TextField(
                controller: b,
                minLines: 6,
                maxLines: 10,
                style: N.t(s: 13),
                decoration: _dec(k == 'script' ? 'Comandos (um por linha)' : 'Texto do prompt',
                    hint: k == 'script' ? 'resumir minha agenda\nalarme 07:30\nrotina: carregador => drive: backup' : null),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('CANCELAR', style: N.t(c: N.dim))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('SALVAR', style: N.t(c: N.cyan, w: FontWeight.w700))),
          ],
        ),
      ),
    );
    if (ok != true || n.text.trim().isEmpty || b.text.trim().isEmpty) return;
    await widget.library.upsert(LibItem(it?.id ?? LibraryStore.newId(), k, n.text.trim(), b.text));
    _changed();
  }


  // ---------- Segurança do tablet ----------
  Widget _lvl(int l) => Icon(
      switch (l) { 0 => Icons.check_circle, 1 => Icons.warning_amber_rounded, 2 => Icons.error, _ => Icons.info_outline },
      size: 18,
      color: switch (l) { 0 => N.green, 1 => N.amber, 2 => N.red, _ => N.dim });

  Widget _chk(int level, String title, String sub, {String? fixLabel, VoidCallback? fix}) => _card(
        child: Row(children: [
          _lvl(level),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: N.t(w: FontWeight.w700, s: 13)),
              Text(sub, style: N.t(c: N.dim, s: 11)),
            ]),
          ),
          if (fix != null && level != 0) NBtn(fixLabel ?? 'Corrigir', accent: level == 2, onTap: fix),
        ]),
      );

  Widget _secTab() {
    final sec = _sec;
    final loaded = sec.isNotEmpty;
    // Verificações pontuadas: [nível, peso]
    final secure = sec['secure'] == true;
    final enc = sec['encrypted'];
    final adb = sec['adb'] == true;
    final dev = sec['dev'] == true;
    final root = sec['root'] == true;
    final patch = '${sec['patch'] ?? ''}';
    int patchLvl = 1;
    String patchSub = 'Não foi possível ler o patch de segurança.';
    final d = DateTime.tryParse(patch);
    if (d != null) {
      final months = DateTime.now().difference(d).inDays / 30;
      patchLvl = months <= 6 ? 0 : (months <= 12 ? 1 : 2);
      patchSub = 'Patch de $patch (${months.round()} meses). '
          '${patchLvl == 0 ? 'Em dia.' : 'Procure atualização do sistema em Ajustes > Sistema.'}';
    }
    final checks = <List<int>>[
      [secure ? 0 : 2, 30],
      [enc == false ? 2 : 0, 15],
      [patchLvl, 15],
      [adb ? 2 : 0, 10],
      [dev ? 1 : 0, 5],
      [root ? 2 : 0, 20],
      [s.osLock || s.lockConfig ? 0 : 1, 5],
    ];
    var score = 0;
    for (final c in checks) {
      score += c[0] == 0 ? c[1] : (c[0] == 1 ? (c[1] / 2).round() : 0);
    }
    final col = score >= 85 ? N.green : (score >= 60 ? N.amber : N.red);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Segurança do tablet', sub: 'Verificação real do aparelho e do que o OpenEXE pode acessar.'),
      _card(
        edge: col,
        child: Row(children: [
          Text(loaded ? '$score' : '--', style: N.t(c: col, s: 34, w: FontWeight.w700)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(score >= 85 ? 'Tablet bem protegido' : (score >= 60 ? 'Dá para melhorar' : 'Atenção: há riscos'),
                  style: N.t(c: col, w: FontWeight.w700)),
              Text('Nota de 0 a 100 sobre bloqueio de tela, criptografia, patch, depuração e root.',
                  style: N.t(c: N.dim, s: 11)),
            ]),
          ),
          NBtn('Verificar de novo', onTap: _loadSecOpt),
        ]),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        NBtn('Bloquear OpenEXE agora', accent: true, onTap: () {
          Navigator.pop(context);
          widget.lockNow();
        }),
        NBtn('Limpar área de transferência', onTap: () async {
          await Clipboard.setData(const ClipboardData(text: ''));
          await widget.clip.clearUnpinned();
          _snack('Área de transferência limpa (itens fixados foram mantidos).');
        }),
        NBtn('Apagar chaves e tokens', onTap: _wipeKeys),
      ]),
      const SizedBox(height: 14),
      Text('Aparelho', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      if (!loaded) Text('Lendo o aparelho…', style: N.t(c: N.dim, s: 12)),
      if (loaded) ...[
        _chk(secure ? 0 : 2, 'Bloqueio de tela do Android',
            secure ? 'PIN, senha, padrão ou biometria ativos.' : 'Sem bloqueio de tela: qualquer pessoa abre o tablet.',
            fixLabel: 'Definir bloqueio', fix: () => NativeBridge.openSettings('security')),
        _chk(enc == false ? 2 : 0, 'Armazenamento criptografado',
            enc == false ? 'Os dados não estão criptografados.' : 'Criptografia do armazenamento ativa.',
            fixLabel: 'Segurança', fix: () => NativeBridge.openSettings('security')),
        _chk(patchLvl, 'Atualização de segurança do Android', patchSub,
            fixLabel: 'Ajustes', fix: () => NativeBridge.openSettings('security')),
        _chk(adb ? 2 : 0, 'Depuração USB', adb ? 'Ligada: um computador conectado pode acessar o tablet.' : 'Desligada.',
            fixLabel: 'Desligar', fix: () => NativeBridge.openSettings('developer')),
        _chk(dev ? 1 : 0, 'Opções do desenvolvedor', dev ? 'Ligadas. Desligue se não estiver usando.' : 'Desligadas.',
            fixLabel: 'Abrir', fix: () => NativeBridge.openSettings('developer')),
        _chk(root ? 2 : 0, 'Root', root ? 'Foram encontrados sinais de root (su). Apps podem ter controle total.' : 'Nenhum sinal de root.'),
        _chk(3, 'Instalar apps desconhecidos (OpenEXE)',
            sec['installUnknown'] == true
                ? 'Liberado só para o OpenEXE instalar as atualizações. Normal.'
                : 'Bloqueado. Libere só se for instalar atualizações do OpenEXE.',
            fixLabel: 'Gerenciar', fix: () => NativeBridge.openSettings('installunknown')),
        _chk(3, 'Modelo e Android',
            '${sec['model'] ?? ''} · Android ${sec['release'] ?? ''} (API ${sec['sdk'] ?? ''})'),
      ],
      const SizedBox(height: 14),
      Text('Proteções do OpenEXE', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      _card(
        child: Column(children: [
          _switch('Tela de bloqueio do OpenEXE', 'Pede digital/PIN ao abrir e ao voltar depois do tempo escolhido.',
              s.osLock, s.setOsLock),
          _switch('Proteger a CONFIG', 'Pede digital/PIN para abrir as configurações.', s.lockConfig, s.setLockConfig),
          _switch('Bloquear o Vault do Notia', 'Pede digital/PIN para ver as notas depois de 5 min fora.', s.lockVault,
              s.setLockVault),
        ]),
      ),
      _chk(0, 'Chaves de API criptografadas', 'Guardadas no Keystore do Android (criptografia por hardware quando existe).'),
      const SizedBox(height: 14),
      Text('Acessos concedidos ao OpenEXE', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      _chk(_a11y ? 1 : 3, 'Controle de apps (acessibilidade)',
          _a11y ? 'Ativo: o agente lê a tela e toca nos apps. Desligue se não usar o agente.' : 'Desligado.',
          fixLabel: 'Gerenciar', fix: () => NativeBridge.openSettings('accessibility')),
      _chk(_notif ? 1 : 3, 'Ler notificações',
          _notif ? 'Ativo: o OpenEXE lê as notificações recebidas.' : 'Desligado.',
          fixLabel: 'Gerenciar', fix: () => NativeBridge.openSettings('notifications')),
      for (final e in _perms.entries)
        _chk(3, e.key, e.value.isGranted ? 'Permitido.' : 'Não permitido.',
            fixLabel: 'Permissões', fix: () async {
          await NativeBridge.openSettings('appdetails');
        }),
      Text('Dica: o OpenEXE não pode trocar o bloqueio de tela do Android; ele só adiciona uma camada por cima.',
          style: N.t(c: N.dim, s: 11)),
    ]);
  }

  Future<void> _wipeKeys() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text('Apagar chaves e tokens?', style: N.t(c: N.red, w: FontWeight.w700)),
        content: Text(
            'Remove as chaves de IA, o token do GitHub, os provedores próprios e os conectores. '
            'Notas e configurações continuam. Você terá que colar as chaves de novo.',
            style: N.t(s: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('CANCELAR', style: N.t(c: N.dim))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('APAGAR', style: N.t(c: N.red, w: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    await s.setGroqKey('');
    await s.setGeminiKey('');
    await s.setOpenrouterKey('');
    await s.setHfToken('');
    await s.setGhToken('');
    await s.setCustomProviders([]);
    await s.setConnectorsJson('[]');
    for (final k in ['kgroq', 'kgemini', 'kopenrouter', 'ghtok']) {
      _c[k]?.clear();
    }
    _snack('Chaves apagadas.');
    _changed();
  }

  // ---------- Otimização ----------
  String _mb(num b) => b >= 1024 * 1024 * 1024
      ? '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
      : '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';

  Widget _bar(String label, double pct, String right, {Color? c}) {
    final col = c ?? (pct >= 90 ? N.red : (pct >= 75 ? N.amber : N.cyan));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: N.t(s: 12, w: FontWeight.w700))),
          Text(right, style: N.t(c: N.dim, s: 11)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0), minHeight: 6, backgroundColor: N.line2, valueColor: AlwaysStoppedAnimation(col)),
        ),
      ]),
    );
  }

  Future<void> _applyProfile(String m) async {
    await s.setPerfMode(m);
    if (m == 'eco') {
      await s.setWakeOn(false);
      await s.setKeepAlive(false);
    }
    _changed();
    _snack(switch (m) {
      'eco' => 'Perfil econômico: palavra de ativação e segundo plano desligados, monitor a cada 10 s.',
      'desempenho' => 'Perfil desempenho: monitor a cada 2 s.',
      _ => 'Perfil equilibrado.',
    });
  }

  Widget _optTab() {
    final cacheB = (_opt['cacheBytes'] as num?) ?? 0;
    final ignoring = _opt['ignoringBattery'] == true;
    final saver = _opt['powerSave'] == true;
    final mode = s.perfMode;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Otimização', sub: 'Leituras reais do tablet e limpezas seguras. O Android não deixa um app matar outros apps.'),
      _card(
        child: ValueListenableBuilder<SysStats>(
          valueListenable: widget.monitor.stats,
          builder: (c, st, _) => Column(children: [
            _bar('RAM', st.ramPct.toDouble(), '${st.ramUsedGb.toStringAsFixed(1)} / ${st.ramTotalGb.toStringAsFixed(1)} GB'),
            _bar('Armazenamento', st.storPct.toDouble(),
                '${st.storUsedGb.toStringAsFixed(0)} / ${st.storTotalGb.toStringAsFixed(0)} GB'),
            _bar('CPU', st.cpuPct < 0 ? 0 : st.cpuPct.toDouble(), st.cpuPct < 0 ? 'indisponível' : '${st.cpuPct}% · ${st.cpuNote}'),
            _bar('Temperatura', st.temp < 0 ? 0 : (st.temp / 60 * 100), st.temp < 0 ? 'indisponível' : '${st.temp.toStringAsFixed(0)} °C · ${st.tempNote}',
                c: st.temp >= 45 ? N.red : (st.temp >= 40 ? N.amber : N.green)),
          ]),
        ),
      ),
      Text('Perfil do OpenEXE', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        NBtn('Econômico', accent: mode == 'eco', onTap: () => _applyProfile('eco')),
        NBtn('Equilibrado', accent: mode == 'equilibrado', onTap: () => _applyProfile('equilibrado')),
        NBtn('Desempenho', accent: mode == 'desempenho', onTap: () => _applyProfile('desempenho')),
      ]),
      const SizedBox(height: 4),
      Text('Econômico desliga palavra de ativação e segundo plano e lê o monitor a cada 10 s. '
          'Os WebViews já pausam sozinhos quando o app sai da tela.',
          style: N.t(c: N.dim, s: 11)),
      const SizedBox(height: 14),
      Text('Limpeza', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      _card(
        child: Column(children: [
          _actRow('Cache do OpenEXE', _mb(cacheB), 'Limpar', () async {
            final n = await NativeBridge.clearCache();
            _snack('Liberados ${_mb(n)}.');
            await _loadSecOpt();
          }),
          _actRow('Cache de respostas da IA', '$_aiCache respostas guardadas', 'Limpar', () async {
            await widget.brain.clearCache();
            _snack('Cache de IA limpo.');
            await _loadSecOpt();
          }),
          _actRow('Histórico de eventos', '$_history registros', 'Apagar > 30 dias', () async {
            final n = await widget.brain.pruneHistory(days: 30);
            _snack('$n registros antigos apagados.');
            await _loadSecOpt();
          }),
          _actRow('Banco de dados do Notia', 'Compacta e recupera espaço', 'Compactar', () async {
            await widget.brain.vacuum();
            _snack('Banco compactado.');
          }),
          _actRow('Histórico da área de transferência', 'Itens fixados são mantidos', 'Limpar', () async {
            await widget.clip.clearUnpinned();
            _snack('Histórico limpo.');
          }),
        ]),
      ),
      const SizedBox(height: 14),
      Text('Bateria e segundo plano', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      _chk(ignoring ? 0 : 3, 'Não otimizar a bateria do OpenEXE',
          ignoring ? 'O Android não vai suspender o OpenEXE. Bom para palavra de ativação e rotinas.'
              : 'Recomendado se usar rotinas, alarmes e palavra de ativação, para o Android não encerrar o app.',
          fixLabel: 'Permitir', fix: () => NativeBridge.openSettings('ignorebattery')),
      _chk(saver ? 1 : 0, 'Economia de bateria do Android',
          saver ? 'Ligada: pode atrasar rotinas e sincronizações.' : 'Desligada.',
          fixLabel: 'Ajustes', fix: () => NativeBridge.openSettings('batterysaver')),
      const SizedBox(height: 8),
      Text('Ver no Android', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        NBtn('Uso da bateria', onTap: () => NativeBridge.openSettings('usage')),
        NBtn('Armazenamento', onTap: () => NativeBridge.openSettings('storage')),
        NBtn('Todos os apps', onTap: () => NativeBridge.openSettings('apps')),
        NBtn('Uso de dados', onTap: () => NativeBridge.openSettings('data')),
        NBtn('Opções do desenvolvedor', onTap: () => NativeBridge.openSettings('developer')),
        NBtn('Atualizar leituras', onTap: _loadSecOpt),
      ]),
      const SizedBox(height: 8),
      Text('Para o tablet parecer mais rápido: em Opções do desenvolvedor, ponha as três escalas de animação em 0,5x.',
          style: N.t(c: N.dim, s: 11)),
    ]);
  }

  Widget _actRow(String t, String sub, String btn, Future<void> Function() on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: N.t(s: 13, w: FontWeight.w700)),
              Text(sub, style: N.t(c: N.dim, s: 11)),
            ]),
          ),
          NBtn(btn, onTap: () => on()),
        ]),
      );


  // ---------- Dev · Termux (TAB DEV-IA) ----------
  Widget _step(int n, String title, String sub, bool done, List<Widget> actions) => _card(
        edge: done ? N.green.withOpacity(0.5) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(done ? Icons.check_circle : Icons.looks_one_outlined, size: 18, color: done ? N.green : N.dim),
            const SizedBox(width: 8),
            Expanded(child: Text('$n. $title', style: N.t(w: FontWeight.w700, s: 13))),
          ]),
          const SizedBox(height: 4),
          Text(sub, style: N.t(c: N.dim, s: 11)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: actions),
        ]),
      );

  Future<void> _termRun(String cmd) async {
    setState(() {
      _busy.add('term');
      _termOut = '\$ $cmd\n…';
    });
    final r = await widget.termuxService.run(cmd, dir: s.devDir);
    if (!mounted) return;
    setState(() {
      _busy.remove('term');
      final o = r.tail(3000);
      _termOut = '\$ $cmd\n${r.error != null ? '[erro] ${r.error}\n' : ''}$o${r.error == null ? '\n[código ${r.exit}]' : ''}';
    });
  }

  Future<void> _loadProjects() async {
    final r = await widget.termuxService.run('ls -1', dir: s.devDir);
    if (!mounted) return;
    setState(() => _projects = r.ok ? r.stdout.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : []);
    if (!r.ok) _snack(r.error ?? 'Não consegui listar.');
  }

  Widget _devTab() {
    final tx = _tx;
    final inst = tx?.installed == true, perm = tx?.perm == true;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Dev · Termux', sub: 'O terminal Linux do tablet. A IA cria, roda e corrige projetos aqui dentro. Preparo feito uma vez.'),
      _step(1, 'Instalar o Termux', 'Use a versão do F-Droid ou do GitHub. A da Play Store é antiga e não funciona com o OpenEXE.', inst, [
        NBtn('Abrir página (F-Droid)', accent: !inst, onTap: () => launchUrl(Uri.parse('https://f-droid.org/packages/com.termux/'), mode: LaunchMode.externalApplication)),
        NBtn('Verificar', onTap: _loadSecOpt),
      ]),
      _step(2, 'Dar permissão ao OpenEXE', 'O Android pergunta se o OpenEXE pode executar comandos no Termux. Toque em Permitir.', perm, [
        NBtn('Dar permissão', accent: inst && !perm, onTap: () async {
          await TermuxService.requestPermission();
          await Future<void>.delayed(const Duration(seconds: 2));
          await _loadSecOpt();
        }),
        NBtn('Verificar', onTap: _loadSecOpt),
      ]),
      _step(3, 'Preparar o ambiente (uma vez)', 'Copie o comando, abra o Termux, cole e dê Enter. Instala git, python, node e libera o OpenEXE. Demora alguns minutos.', false, [
        NBtn('Copiar comando', accent: true, onTap: () {
          Clipboard.setData(const ClipboardData(text: TermuxService.bootstrap));
          _snack('Comando copiado. Cole no Termux.');
        }),
        NBtn('Abrir Termux', onTap: () => TermuxService.open()),
      ]),
      _step(4, 'Testar a conexão', 'Roda um comando de verdade no Termux e mostra a versão do que está instalado.', false, [
        NBtn(_busy.contains('term') ? 'Testando…' : 'Testar agora', accent: perm, onTap: _busy.contains('term') ? null : () => _termRun('echo conectado; uname -m; python --version; node --version; git --version')),
      ]),
      const SizedBox(height: 6),
      Text('Agente de desenvolvimento', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _switch('Executar sem perguntar', 'Comandos comuns rodam direto. Os arriscados (apagar, sudo, git push…) ainda pedem confirmação.',
              s.devAuto, s.setDevAuto),
          Row(children: [
            Expanded(child: TextField(controller: ctl('devdir', s.devDir), style: N.t(s: 13), decoration: _dec('Pasta dos projetos (dentro da home do Termux)'))),
            const SizedBox(width: 8),
            NBtn('Salvar', onTap: () async {
              await s.setDevDir(ctl('devdir').text);
              _snack('Pasta salva.');
              _changed();
            }),
          ]),
        ]),
      ),
      Text('Peça pelo console. Exemplos:', style: N.t(c: N.dim, s: 12)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in const [
          'dev crie um site de uma página para uma loja de carros com WhatsApp',
          'dev crie uma API em Node com rota /saude e teste',
          'dev crie um script python que organiza a pasta Downloads por tipo',
        ])
          NBtn(e.substring(4, e.length > 48 ? 48 : e.length) + (e.length > 48 ? '…' : ''), onTap: () {
            Navigator.pop(context);
            widget.runCommand(e);
          }),
      ]),
      const SizedBox(height: 14),
      Text('Terminal rápido', style: N.t(c: N.cyan, w: FontWeight.w700)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: TextField(controller: ctl('term'), style: N.t(s: 13), decoration: _dec('Comando (roda dentro da pasta dos projetos)'),
            onSubmitted: (v) => v.trim().isEmpty ? null : _termRun(v.trim()))),
        const SizedBox(width: 8),
        NBtn('Executar', accent: true, onTap: _busy.contains('term') ? null : () => ctl('term').text.trim().isEmpty ? null : _termRun(ctl('term').text.trim())),
      ]),
      if (_termOut.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: N.border, width: 0.7), borderRadius: BorderRadius.circular(6)),
          child: SelectableText(_termOut, style: N.t(c: N.text, s: 12)),
        ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text('Projetos', style: N.t(c: N.cyan, w: FontWeight.w700))),
        NBtn('Atualizar lista', onTap: _loadProjects),
      ]),
      const SizedBox(height: 6),
      if (_projects.isEmpty) Text('Nenhum projeto ainda (ou lista não carregada).', style: N.t(c: N.dim, s: 12)),
      for (final pj in _projects)
        _card(
          child: Row(children: [
            const Icon(Icons.folder_outlined, size: 18, color: N.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text(pj, style: N.t(s: 13))),
            NBtn('Servir no Dock', onTap: () {
              Navigator.pop(context);
              widget.runCommand('servir $pj');
            }),
          ]),
        ),
    ]);
  }


  // ---------- Voz do assistente ----------
  Widget _slider(String label, double v, double min, double max, String shown, Future<void> Function(double) save,
          {int? div}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label: $shown', style: N.t(s: 13)),
        Slider(
          value: v.clamp(min, max),
          min: min,
          max: max,
          divisions: div,
          activeColor: N.cyan,
          onChanged: (x) async {
            await save(x);
            if (mounted) setState(() {});
          },
          onChangeEnd: (_) => widget.tts.refresh(),
        ),
      ]);

  Future<void> _speakTest() async {
    setState(() => _ttsNote = 'Falando…');
    await widget.tts.refresh();
    await widget.tts.speak(ctl('ttstest', 'Olá! Esta é a voz do seu assistente. Como posso ajudar?').text);
    if (mounted) setState(() => _ttsNote = widget.tts.lastNote);
  }

  Widget _voiceTab() {
    if (!_voicesLoaded) {
      _voicesLoaded = true;
      widget.tts.systemVoices().then((v) {
        if (mounted) setState(() => _sysVoices = v);
      });
    }
    final gem = s.ttsEngine == 'gemini';
    final cur = s.ttsVoice;
    final names = _sysVoices.map((e) => e['name']!).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _h('Voz', sub: 'Como o assistente fala com você. Teste aqui antes de usar no console.'),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _switch('Falar as respostas', 'O console lê em voz alta o que a IA responde.', s.speakReplies, s.setSpeakReplies),
          const SizedBox(height: 4),
          Text('Motor de voz', style: N.t(s: 13, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            NBtn('Voz do tablet', accent: !gem, onTap: () async {
              await s.setTtsEngine('sistema');
              _changed();
            }),
            NBtn('Gemini (mais natural)', accent: gem, onTap: () async {
              await s.setTtsEngine('gemini');
              _changed();
            }),
          ]),
          const SizedBox(height: 6),
          Text(
              gem
                  ? 'Gemini: voz bem natural, 30 vozes, mas o plano grátis tem limite de pedidos por minuto e por dia. '
                      'Quando estourar, o OpenEXE fala com a voz do tablet por 2 minutos e volta depois. '
                      'Frases com mais de 900 letras também usam a voz do tablet.'
                  : 'Voz do tablet: instantânea, funciona sem internet e sem limite. Ideal para conversar bastante.',
              style: N.t(c: N.dim, s: 11)),
        ]),
      ),
      if (!gem)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Voz do tablet', style: N.t(c: N.cyan, w: FontWeight.w700)),
            const SizedBox(height: 8),
            if (names.isEmpty)
              Text('Nenhuma voz em português encontrada. Instale em Ajustes do Android > Sistema > Idiomas > '
                  'Saída de texto para fala > Google > Instalar dados de voz.',
                  style: N.t(c: N.amber, s: 11))
            else
              Row(children: [
                Expanded(child: Text('Voz', style: N.t(s: 13))),
                DropdownButton<String>(
                  value: names.contains(cur) ? cur : null,
                  hint: Text('padrão do sistema', style: N.t(c: N.dim, s: 13)),
                  dropdownColor: N.field,
                  underline: const SizedBox(),
                  style: N.t(s: 13),
                  items: [for (final v in _sysVoices) DropdownMenuItem(value: v['name'], child: Text(v['name']!))],
                  onChanged: (n) async {
                    final v = _sysVoices.firstWhere((e) => e['name'] == n);
                    await s.setTtsVoice(v['name']!, v['locale']!);
                    await widget.tts.refresh();
                    _changed();
                  },
                ),
              ]),
            _slider('Velocidade', s.ttsRate, 0.5, 2.0, '${s.ttsRate.toStringAsFixed(2)}x', s.setTtsRate, div: 30),
            _slider('Tom (grave ↔ agudo)', s.ttsPitch, 0.5, 2.0, s.ttsPitch.toStringAsFixed(2), s.setTtsPitch, div: 30),
            _slider('Volume', s.ttsVolume, 0.2, 1.0, '${(s.ttsVolume * 100).round()}%', s.setTtsVolume, div: 8),
          ]),
        ),
      if (gem)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Voz do Gemini', style: N.t(c: N.cyan, w: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Voz', style: N.t(s: 13))),
              DropdownButton<String>(
                value: TtsService.geminiVoices.contains(s.geminiVoice) ? s.geminiVoice : 'Kore',
                dropdownColor: N.field,
                underline: const SizedBox(),
                style: N.t(s: 13),
                items: [for (final v in TtsService.geminiVoices) DropdownMenuItem(value: v, child: Text(v))],
                onChanged: (v) async {
                  await s.setGeminiVoice(v ?? 'Kore');
                  _changed();
                },
              ),
            ]),
            _slider('Velocidade', s.geminiRate, 0.75, 1.6, '${s.geminiRate.toStringAsFixed(2)}x', s.setGeminiRate, div: 17),
            Text(s.geminiKey.isEmpty ? 'Falta a chave do Gemini (aba IAs).' : 'Usa a mesma chave do Gemini da aba IAs.',
                style: N.t(c: s.geminiKey.isEmpty ? N.amber : N.dim, s: 11)),
          ]),
        ),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Testar', style: N.t(c: N.cyan, w: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: ctl('ttstest', 'Olá! Esta é a voz do seu assistente. Como posso ajudar?'),
            minLines: 2,
            maxLines: 4,
            style: N.t(s: 13),
            decoration: _dec('Texto de teste'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            NBtn('Falar', accent: true, onTap: _speakTest),
            const SizedBox(width: 8),
            NBtn('Parar', onTap: () => widget.tts.stop()),
            const SizedBox(width: 10),
            Expanded(child: Text(_ttsNote, style: N.t(c: N.amber, s: 11))),
          ]),
        ]),
      ),
    ]);
  }

  // ---------- Estrutura ----------
  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => _aiTab(),
      1 => _repoTab(),
      2 => _connTab(),
      3 => _pluginTab(),
      4 => _modTab(),
      5 => _libTab(),
      6 => _secTab(),
      7 => _optTab(),
      8 => _devTab(),
      _ => _voiceTab(),
    };
    return Scaffold(
      backgroundColor: N.bg,
      body: SafeArea(
        child: Column(children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line2))),
            child: Row(children: [
              Text('PAINEL DE CONTROLE', style: N.t(c: N.cyan, w: FontWeight.w700, s: 15, ls: 1)),
              const Spacer(),
              NBtn('CONFIG completa', onTap: widget.openConfig),
              const SizedBox(width: 8),
              NBtn('FECHAR', accent: true, onTap: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: Row(children: [
              Container(
                width: 190,
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: N.line2))),
                child: ListView(children: [
                  for (var i = 0; i < _tabs.length; i++)
                    InkWell(
                      onTap: () => setState(() => _tab = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        color: _tab == i ? N.cyan.withOpacity(0.08) : null,
                        child: Row(children: [
                          Icon(_tabs[i][1] as IconData, size: 18, color: _tab == i ? N.cyan : N.dim),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(_tabs[i][0] as String,
                                  style: N.t(c: _tab == i ? N.cyan : N.text, s: 13, w: FontWeight.w700))),
                        ]),
                      ),
                    ),
                ]),
              ),
              Expanded(child: body),
            ]),
          ),
        ]),
      ),
    );
  }
}
