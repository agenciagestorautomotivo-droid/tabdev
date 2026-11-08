import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

import 'clipboard_popup.dart';
import 'config_dialog.dart';
import 'global_search.dart';
import 'panels/ai_hub_panel.dart';
import 'panels/apps_panel.dart';
import 'panels/brain_panel.dart';
import 'panels/console_panel.dart';
import 'panels/dock_panel.dart';
import 'services/ai_router.dart';
import 'services/app_agent_service.dart';
import 'services/clipboard_history_service.dart';
import 'services/device_kit.dart';
import 'services/dock_model.dart';
import 'services/gallery_service.dart';
import 'services/github_sync_service.dart';
import 'services/google_services.dart';
import 'services/hybrid_calculator_service.dart';
import 'services/keyboard_mode.dart';
import 'services/local_calendar_service.dart';
import 'services/lock_service.dart';
import 'services/media_service.dart';
import 'services/native_bridge.dart';
import 'services/notia_brain.dart';
import 'services/notification_service.dart';
import 'services/ocr_service.dart';
import 'services/phone_service.dart';
import 'services/place_service.dart';
import 'services/power_service.dart';
import 'services/repo_store.dart';
import 'services/routine_service.dart';
import 'services/settings_store.dart';
import 'services/supabase_sync_service.dart';
import 'services/system_monitor_service.dart';
import 'services/tasks_service.dart';
import 'services/text_utils.dart';
import 'services/update_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final settings = await SettingsStore.load();
  final brain = await NotiaBrain.open();
  runApp(OpenExeApp(settings: settings, brain: brain));
}

class OpenExeApp extends StatelessWidget {
  const OpenExeApp({super.key, required this.settings, required this.brain});
  final SettingsStore settings;
  final NotiaBrain brain;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenEXE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: N.bg,
        colorScheme: const ColorScheme.dark(primary: N.cyan, surface: N.bg),
      ),
      home: Shell(settings: settings, brain: brain),
    );
  }
}

/// Módulos que podem ocupar cada posição (ids usados em settings.slots5).
const _moduleNames = [
  'Q1 · Console de IA',
  'Q2 · Hub de IAs',
  'Q3 · NotIA (cérebro e memória)',
  'Q4 · Dock e navegador',
  'Q5 · Apps instalados',
];
const _posNames = [
  'Coluna esquerda · cima',
  'Coluna esquerda · baixo',
  'Coluna direita · cima',
  'Coluna direita · meio',
  'Coluna direita · baixo',
];
const _blue = Color(0xFF60A5FA);

class Shell extends StatefulWidget {
  const Shell({super.key, required this.settings, required this.brain});
  final SettingsStore settings;
  final NotiaBrain brain;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  static const _sys = MethodChannel('notia/system');

  late final AiRouter _router = AiRouter(widget.brain, widget.settings);
  late final HybridCalculatorService _calc = HybridCalculatorService(widget.brain, _router);
  late final GitHubSyncService _gh = GitHubSyncService(widget.settings);
  late final SupabaseSyncService _sb = SupabaseSyncService(widget.settings, widget.brain);
  final GoogleAuthService _google = GoogleAuthService();
  late final DriveBackupService _drive =
      DriveBackupService(_google, widget.brain, widget.settings);
  late final CalendarService _calendar = CalendarService(_google, widget.brain);
  late final MediaService _media = MediaService(widget.settings, widget.brain.vault);

  late final OcrService _ocr = OcrService(widget.brain);
  late final PowerService _power = PowerService();
  late final RoutineService _routines = RoutineService(widget.settings);
  late final DeviceKit _kit = DeviceKit(
    agent: AppAgentService(_router, widget.brain),
    notifs: NotificationService(),
    phone: PhoneService(),
    ocr: _ocr,
    gallery: GalleryService(widget.brain, _ocr),
    localCal: LocalCalendarService(widget.brain),
    clip: ClipboardHistoryService(widget.settings),
    routines: _routines,
    places: PlaceService(widget.settings),
    power: _power,
    lock: LockService(),
  );

  // OpenEXE
  late final DockModel _dock = DockModel(widget.settings);
  final SystemMonitorService _monitor = SystemMonitorService();
  final KeyboardMode _kbd = KeyboardMode();
  final TasksService _tasks = TasksService();
  late final RepoStore _repos = RepoStore(widget.settings);
  late final UpdateService _update = UpdateService(widget.settings);

  StreamSubscription? _events;
  Timer? _placeTimer;
  Timer? _minuteTimer;
  DateTime? _pausedAt;
  late bool _vaultLocked = widget.settings.lockVault;
  late bool _focus = widget.settings.focusMode;
  bool _btOn = false;
  Map<String, dynamic>? _nextEvent;

  final _voiceStatus = ValueNotifier<String>('PRONTA');
  final _consoleKey = GlobalKey<ConsolePanelState>();
  final _dockKey = GlobalKey<DockPanelState>();
  final _hubKey = GlobalKey<AiHubPanelState>();
  final _brainKey = GlobalKey();

  Timer? _clock;
  StreamSubscription? _net;
  DateTime _now = DateTime.now();
  bool _online = true;
  bool _wifi = false;

  late double _col = widget.settings.col5;
  late double _left = widget.settings.left5;
  late double _ra = widget.settings.rightA5;
  late double _rb = widget.settings.rightB5;
  late List<int> _slots = widget.settings.slots5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _initNet();
    _initDevice();
    _initOpenExe();
    _sb.onNotification = (m) {
      _consoleKey.currentState?.say('Cloud: $m', color: N.amber);
      _consoleKey.currentState?.speak(m);
    };
    _sb.connect();
    _google.signInSilently().then((ok) {
      if (ok) {
        _drive.status.value = 'SYNCED';
        _drive.maybeAutoBackup();
      }
    });
  }

  Future<void> _initOpenExe() async {
    _dock.refresh();
    _update.start();
    _update.addListener(_onUpdate);
    Future<void>.delayed(const Duration(seconds: 8), () => _update.check(wifi: _wifi));
    _monitor.start();
    await _kbd.init();
    await _tasks.load();
    _btOn = await NativeBridge.bluetoothOn();
    if (mounted) setState(() {});
    _refreshNext();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshNext();
      _tasks.load();
    });
    NativeBridge.events.where((e) => e['type'] == 'bt').listen((e) {
      if (mounted) setState(() => _btOn = e['on'] == true);
    });
  }

  UpdateState _lastUpd = UpdateState.idle;
  void _onUpdate() {
    if (!mounted) return;
    if (_update.state == UpdateState.ready && _lastUpd != UpdateState.ready) {
      _toast('Atualização do OpenEXE pronta. Toque em ATUALIZAR no topo para instalar.');
    }
    _lastUpd = _update.state;
    setState(() {});
  }

  Future<void> _installUpdate() async {
    if (_update.state == UpdateState.available) {
      await _update.download();
      return;
    }
    final r = await _update.install();
    if (r == 'permissao') {
      _toast('Libere "instalar apps desconhecidos" para o OpenEXE e toque em ATUALIZAR de novo.');
    }
  }

  Future<void> _refreshNext() async {
    final n = await _kit.localCal.next();
    if (mounted) setState(() => _nextEvent = n);
  }

  Future<void> _initNet() async {
    final c = Connectivity();
    bool ok(dynamic r) =>
        r is List ? !r.contains(ConnectivityResult.none) : r != ConnectivityResult.none;
    bool wifi(dynamic r) => r is List
        ? (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet))
        : (r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
    try {
      final r = await c.checkConnectivity();
      if (mounted) {
        setState(() {
          _online = ok(r);
          _wifi = wifi(r);
          _update.setWifi(_wifi);
        });
      }
    } catch (_) {}
    _net = c.onConnectivityChanged.listen((r) {
      if (mounted) {
        setState(() {
          _online = ok(r);
          _wifi = wifi(r);
          _update.setWifi(_wifi);
        });
      }
    });
  }

  // ---------- Recursos do aparelho ----------
  ConsolePanelState? get _console => _consoleKey.currentState;

  Future<void> _initDevice() async {
    // Rotinas executam comandos do próprio console.
    _routines.runner = (cmd, why) async {
      _console?.say('Rotina ($why): $cmd', color: N.cyan);
      _console?.ask(cmd);
    };
    _routines.start();

    // Bateria: carregador e nível baixo viram gatilhos de rotina.
    _power.onPlugged = () => _routines.fire((t) => t == 'carregador', 'carregador ligado');
    _power.level.addListener(() {
      final lv = _power.level.value;
      if (_power.charging) return;
      _routines.fire((t) {
        final m = RegExp(r'^bateria<(\d{1,2})$').firstMatch(t);
        return m != null && lv < int.parse(m.group(1)!);
      }, 'bateria em $lv%');
    });
    await _power.start();

    // Notificações dos outros apps. No modo foco o OpenEXE não fala nem escreve no console.
    _kit.notifs.onNew = (n) {
      final a = norm(n.app);
      if (!_focus && widget.settings.notifSpeak.any((f) => a.contains(norm(f)))) {
        _console?.say('Notificação · ${n.app}: ${n.title}${n.text.isEmpty ? '' : ' — ${clip(n.text, 100)}'}',
            color: N.amber);
        _console?.speak('${n.app}: ${n.title}');
      }
      if (mounted) setState(() {});
      _routines.fire((t) {
        if (!t.startsWith('notif:')) return false;
        final f = t.substring(6);
        return a.contains(f) || norm(n.pkg).contains(f);
      }, 'notificação de ${n.app}');
    };
    await _kit.notifs.init();

    // Eventos vindos do Android: notificações, compartilhar, atalho do painel, parar.
    _events = NativeBridge.events.listen((e) {
      switch (e['type']) {
        case 'notif':
          _kit.notifs.ingest(e);
        case 'share':
          _console?.handleShared(e);
        case 'action':
          if (e['action'] == 'dictate') {
            _console?.showKeyboard();
            _console?.toggleMic();
          }
        case 'agent_stop':
          _kit.agent.stop();
          _console?.say('Parando o agente…', color: N.amber);
      }
    });

    // Chegada a lugares salvos (checa a cada 10 min e ao voltar ao app).
    _placeTimer = Timer.periodic(const Duration(minutes: 10), (_) => _checkPlace());
  }

  Future<void> _checkPlace() async {
    if (_power.low) return;
    final arrived = await _kit.places.checkArrival();
    if (arrived != null) {
      _console?.say('Você chegou em "$arrived".', color: N.cyan);
      _routines.fire((t) => t == 'local:$arrived', 'chegada em $arrived');
    }
    if (mounted) setState(() {});
  }

  Future<void> _unlockVault() async {
    final ok = await _kit.lock.authenticate('Abrir o Vault do OpenEXE');
    if (ok && mounted) setState(() => _vaultLocked = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _minuteTimer?.cancel();
    _net?.cancel();
    _events?.cancel();
    _placeTimer?.cancel();
    _routines.dispose();
    _power.dispose();
    _update.removeListener(_onUpdate);
    _update.disposeTimer();
    _monitor.dispose();
    _kbd.dispose();
    _dock.dispose();
    super.dispose();
  }

  // Proteção de bateria: pausa os timers JS dos WebViews e o monitor fora de foco.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    _sys.invokeMethod(resumed ? 'resumeWebTimers' : 'pauseWebTimers').catchError((_) {});
    if (!resumed) {
      _monitor.stop();
      _pausedAt ??= DateTime.now();
    } else {
      _monitor.start();
      final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (widget.settings.lockVault && away.inMinutes >= 5) _vaultLocked = true;
      widget.brain.syncFromVault();
      // Backup automático só no Wi-Fi e com carregador ou bateria acima de 30%.
      if (_power.backupOk(_wifi)) _drive.maybeAutoBackup();
      _dock.refresh();
      _update.check(wifi: _wifi);
      _routines.tick();
      _checkPlace();
      _tasks.load();
      _refreshNext();
      _grabClipboard();
      if (mounted) setState(() {});
    }
  }

  /// O Android só entrega a área de transferência com o app em primeiro plano.
  Future<void> _grabClipboard() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final t = d?.text;
      if (t != null && t.isNotEmpty) await _kit.clip.add(t);
    } catch (_) {}
    await _kit.clip.checkImage();
  }

  // ---------- Ações ----------
  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3)));
  }

  void _openHub(String category, String prompt) {
    Clipboard.setData(ClipboardData(text: prompt));
    _hubKey.currentState?.showCategory(category);
  }

  Future<void> _syncCloud() async {
    final c = _consoleKey.currentState;
    c?.say('Sincronizando com o Drive…');
    final r = await _drive.backup();
    c?.say(r ?? 'Drive: ${_drive.lastError}', color: r != null ? N.green : N.red);
    if (_sb.configured) _sb.backup();
  }

  Future<void> _syncAgenda() async {
    final c = _consoleKey.currentState;
    if (!_google.signedIn && !await _google.signIn()) {
      c?.say(_google.lastError, color: N.red);
      return;
    }
    final lines = await _calendar.sync();
    if (lines == null) {
      c?.say(_calendar.lastError, color: N.red);
    } else if (lines.isEmpty) {
      c?.say('Agenda sincronizada: sem compromissos nas próximas 24 h.', color: N.green);
    } else {
      c?.say('Agenda sincronizada (${lines.length}): ${lines.take(5).join(' · ')}',
          color: N.green);
      c?.speak('Você tem ${lines.length} compromisso${lines.length > 1 ? 's' : ''} nas próximas 24 horas.');
    }
    _refreshNext();
  }

  Future<void> _quick(String which) async {
    final ok = await NativeBridge.quickApp(which);
    if (!ok) _toast('Não encontrei um app para isso neste aparelho.');
  }

  Future<void> _toggleFocus() async {
    final v = !_focus;
    await widget.settings.setFocusMode(v);
    setState(() => _focus = v);
    _toast(v
        ? 'Modo foco ligado: o OpenEXE não fala nem escreve notificações no console.'
        : 'Modo foco desligado.');
  }

  void _toggleKeyboard() {
    if (!_kbd.physical) {
      _toast('Nenhum teclado físico conectado. Usando o teclado virtual.');
      _console?.showKeyboard();
      return;
    }
    _kbd.toggle();
    if (_kbd.useVirtual) _console?.showKeyboard();
    _toast(_kbd.label == 'TECLADO VIRTUAL'
        ? 'Teclado virtual. Toque de novo para voltar ao físico.'
        : 'Teclado físico.');
  }

  Future<void> _globalSearch() => showGlobalSearch(
        context,
        brain: widget.brain,
        dock: _dock,
        clip: _kit.clip,
        onApp: (a) => InstalledApps.startApp(a.packageName),
        onCommand: (c) => _console?.ask(c),
        onText: (t) {
          Clipboard.setData(ClipboardData(text: t));
          _toast('Texto copiado.');
        },
        onNote: (title, body) => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: N.bg,
            shape: RoundedRectangleBorder(
                side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
            title: Text(title, style: N.t(c: N.cyan, w: FontWeight.w700)),
            content: SizedBox(
                width: 520,
                child: SingleChildScrollView(child: Text(body, style: N.t(s: 13)))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text('FECHAR', style: N.t(c: N.dim))),
            ],
          ),
        ),
      );

  Future<void> _quickNote() async {
    final t = TextEditingController();
    final b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text('Nota rápida', style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: t,
                autofocus: true,
                style: N.t(),
                decoration: InputDecoration(labelText: 'Título', labelStyle: N.t(c: N.dim))),
            TextField(
                controller: b,
                style: N.t(),
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(labelText: 'Texto', labelStyle: N.t(c: N.dim))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('CANCELAR', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('SALVAR NO VAULT', style: N.t(c: N.cyan, w: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || t.text.trim().isEmpty) return;
    final saved = await widget.brain.saveNote(t.text.trim(), b.text.trim());
    _toast(saved ? 'Nota salva.' : 'Não consegui salvar a nota.');
  }

  Future<void> _showNotifications() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final l = _kit.notifs.latest(n: 40);
        return Dialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 560,
            height: 480,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: Text('Notificações (${l.length})',
                          style: N.t(c: N.cyan, w: FontWeight.w700, s: 15))),
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _console?.ask('resumir notificações');
                      },
                      child: Text('RESUMIR', style: N.t(c: N.cyan, s: 12, w: FontWeight.w700))),
                  TextButton(
                      onPressed: () async {
                        await _kit.notifs.clear();
                        setD(() {});
                        if (mounted) setState(() {});
                      },
                      child: Text('LIMPAR', style: N.t(c: N.red, s: 12))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('FECHAR', style: N.t(c: N.dim, s: 12))),
                ]),
              ),
              Expanded(
                child: l.isEmpty
                    ? Center(
                        child: Text(
                            'Nenhuma notificação. Se esperava alguma, ative o acesso em CONFIG > Notificações.',
                            textAlign: TextAlign.center,
                            style: N.t(c: N.dim, s: 12)))
                    : ListView(children: [
                        for (final n in l)
                          ListTile(
                            dense: true,
                            leading: Text(n.hhmm, style: N.t(c: N.dim, s: 11)),
                            title: Text('${n.app} · ${n.title}',
                                style: N.t(s: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: n.text.isEmpty
                                ? null
                                : Text(n.text,
                                    style: N.t(c: N.dim, s: 11),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                          ),
                      ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _showAgent() async {
    final c = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text('Agente de apps', style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                _kit.agent.running
                    ? 'O agente está trabalhando agora.'
                    : 'O OpenEXE opera os apps como você faria, com confirmação antes de pagar, enviar ou apagar.',
                style: N.t(c: N.dim, s: 12)),
            const SizedBox(height: 10),
            TextField(
                controller: c,
                autofocus: true,
                style: N.t(),
                decoration: InputDecoration(
                    labelText: 'Ex.: no ElevenLabs, gere o áudio "olá"', labelStyle: N.t(c: N.dim))),
          ]),
        ),
        actions: [
          if (_kit.agent.running)
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _console?.ask('parar');
                },
                child: Text('PARAR', style: N.t(c: N.red, w: FontWeight.w700))),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('FECHAR', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () {
                final t = c.text.trim();
                Navigator.pop(ctx);
                if (t.isNotEmpty) _console?.ask('agente: $t');
              },
              child: Text('EXECUTAR', style: N.t(c: N.cyan, w: FontWeight.w700))),
        ],
      ),
    );
  }

  Future<void> _showRoutines() async {
    final c = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final l = _routines.all;
        return Dialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 560,
            height: 480,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: Text('Rotinas (${l.length})',
                          style: N.t(c: N.cyan, w: FontWeight.w700, s: 15))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('FECHAR', style: N.t(c: N.dim, s: 12))),
                ]),
              ),
              Expanded(
                child: l.isEmpty
                    ? Center(
                        child: Text('Nenhuma rotina ainda.', style: N.t(c: N.dim)))
                    : ListView(children: [
                        for (var i = 0; i < l.length; i++)
                          ListTile(
                            dense: true,
                            leading: Switch(
                              value: l[i].active,
                              activeColor: N.cyan,
                              onChanged: (_) async {
                                await _routines.toggle(i);
                                setD(() {});
                                if (mounted) setState(() {});
                              },
                            ),
                            title: Text('${l[i].label}: ${l[i].command}',
                                style: N.t(s: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: N.red, size: 18),
                              onPressed: () async {
                                await _routines.removeAt(i);
                                setD(() {});
                                if (mounted) setState(() {});
                              },
                            ),
                          ),
                      ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      style: N.t(s: 12),
                      decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Nova: 07:00 resumir minha agenda · carregador => drive: backup',
                          hintStyle: N.t(c: N.dim, s: 11)),
                    ),
                  ),
                  TextButton(
                      onPressed: () {
                        final t = c.text.trim();
                        if (t.isEmpty) return;
                        Navigator.pop(ctx);
                        _console?.ask('rotina: $t');
                      },
                      child: Text('ADICIONAR', style: N.t(c: N.cyan, s: 12, w: FontWeight.w700))),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _showPlace() async {
    final c = TextEditingController();
    final cur = _kit.places.current;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text('Lugar', style: N.t(c: N.cyan, w: FontWeight.w700)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cur == null ? 'Você não está em nenhum lugar salvo.' : 'Você está em: $cur',
                style: N.t(s: 13)),
            const SizedBox(height: 6),
            Text(
                _kit.places.places.isEmpty
                    ? 'Nenhum lugar salvo.'
                    : 'Salvos: ${_kit.places.places.map((e) => e.name).join(', ')}',
                style: N.t(c: N.dim, s: 12)),
            const SizedBox(height: 10),
            TextField(
                controller: c,
                style: N.t(),
                decoration: InputDecoration(
                    labelText: 'Salvar onde estou agora como…', labelStyle: N.t(c: N.dim))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('FECHAR', style: N.t(c: N.dim))),
          TextButton(
              onPressed: () {
                final t = c.text.trim();
                Navigator.pop(ctx);
                if (t.isNotEmpty) _console?.ask('lugar salvar $t');
              },
              child: Text('SALVAR', style: N.t(c: N.cyan, w: FontWeight.w700))),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showTasks() async {
    final c = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 520,
          height: 460,
          child: ValueListenableBuilder<List<TaskItem>>(
            valueListenable: _tasks.items,
            builder: (ctx, l, _) => Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: Text('Tarefas de hoje (${_tasks.done}/${_tasks.total})',
                          style: N.t(c: N.cyan, w: FontWeight.w700, s: 15))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('FECHAR', style: N.t(c: N.dim, s: 12))),
                ]),
              ),
              Expanded(
                child: l.isEmpty
                    ? Center(
                        child: Text('Sem tarefas. Escreva uma abaixo.', style: N.t(c: N.dim)))
                    : ListView(children: [
                        for (var i = 0; i < l.length; i++)
                          CheckboxListTile(
                            dense: true,
                            value: l[i].done,
                            activeColor: N.cyan,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(l[i].text,
                                style: N.t(
                                    c: l[i].done ? N.dim : N.text,
                                    s: 13)),
                            secondary: IconButton(
                                icon: const Icon(Icons.close, color: N.red, size: 18),
                                onPressed: () => _tasks.remove(i)),
                            onChanged: (_) => _tasks.toggle(i),
                          ),
                      ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      style: N.t(s: 13),
                      onSubmitted: (v) {
                        _tasks.add(v);
                        c.clear();
                      },
                      decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Nova tarefa (fica em Notas/tarefas.md do Vault)',
                          hintStyle: N.t(c: N.dim, s: 12)),
                    ),
                  ),
                  TextButton(
                      onPressed: () {
                        _tasks.add(c.text);
                        c.clear();
                      },
                      child: Text('ADICIONAR', style: N.t(c: N.cyan, s: 12, w: FontWeight.w700))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showMonitor() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<SysStats>(
        valueListenable: _monitor.stats,
        builder: (ctx, s, _) => AlertDialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          title: Text('Tablet', style: N.t(c: N.cyan, w: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RAM: ${s.ramUsedGb.toStringAsFixed(1)} de ${s.ramTotalGb.toStringAsFixed(1)} GB (${s.ramPct}%)',
                  style: N.t(s: 13)),
              Text('Memória: ${s.storUsedGb.toStringAsFixed(0)} de ${s.storTotalGb.toStringAsFixed(0)} GB (${s.storPct}%)',
                  style: N.t(s: 13)),
              Text('CPU: ${s.cpuPct < 0 ? '—' : '${s.cpuPct}%'} · ${s.cpuNote}', style: N.t(s: 13)),
              Text('Temperatura: ${s.temp < 0 ? '—' : '${s.temp.toStringAsFixed(1)} °C'} · ${s.tempNote}',
                  style: N.t(s: 13)),
              const SizedBox(height: 10),
              Text(
                  'O Android 13 não deixa apps comuns lerem o uso total da CPU nem o sensor térmico do processador. Quando isso acontece, o OpenEXE estima pela frequência do processador e usa a temperatura da bateria.',
                  style: N.t(c: N.dim, s: 11)),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text('FECHAR', style: N.t(c: N.dim))),
          ],
        ),
      ),
    );
  }

  // ---------- Módulos ----------
  Widget _module(int id) {
    switch (id) {
      case 0:
        return QuadFrame(
          title: 'Q1 · CONSOLE DE IA',
          child: ConsolePanel(
            key: _consoleKey,
            brain: widget.brain,
            router: _router,
            settings: widget.settings,
            voiceStatus: _voiceStatus,
            onOpenUrl: (u) => _dockKey.currentState?.openUrl(u),
            onOpenHub: _openHub,
            onLaunchApp: (n) async => await _dockKey.currentState?.launchByName(n),
            onInstallApp: (n) => _dockKey.currentState?.openStore(n),
            calc: _calc,
            gh: _gh,
            sb: _sb,
            drive: _drive,
            media: _media,
            kit: _kit,
            keyboard: _kbd,
          ),
        );
      case 1:
        return QuadFrame(
          title: 'Q2 · HUB DE IAS',
          child: AiHubPanel(
            key: _hubKey,
            settings: widget.settings,
            repos: _repos,
            runCommand: (c) => _console?.ask(c),
            noteSlugs: () async => [
              for (final n in await widget.brain.notes()) '${n['chave']}'.replaceFirst('nota:', ''),
            ],
          ),
        );
      case 2:
        return QuadFrame(
          title: 'Q3 · NOTIA · CÉREBRO E MEMÓRIA',
          trailing: Text('Vault · SQLite', style: N.t(c: N.dim, s: 11)),
          child: _vaultLocked
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Vault travado', style: N.t(c: N.amber, w: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Use sua digital, rosto ou PIN.', style: N.t(c: N.dim, s: 12)),
                      const SizedBox(height: 12),
                      NBtn('DESTRAVAR', accent: true, onTap: _unlockVault),
                    ],
                  ),
                )
              : BrainPanel(key: _brainKey, brain: widget.brain, onSyncCloud: _syncCloud),
        );
      case 3:
        return QuadFrame(
          title: 'Q4 · DOCK E NAVEGADOR',
          child: DockPanel(
            key: _dockKey,
            model: _dock,
            media: _media,
            onPageText: (text, url) {
              if (text.isEmpty) {
                _consoleKey.currentState?.say('Não consegui ler a página.', color: N.red);
              } else {
                _consoleKey.currentState
                    ?.ask('Resuma em português, em poucas linhas: $text');
              }
            },
          ),
        );
      default:
        return QuadFrame(
          title: 'Q5 · APPS INSTALADOS',
          child: AppsPanel(model: _dock, onStore: () => _dockKey.currentState?.openStore()),
        );
    }
  }

  int _flex(double v) => (v * 1000).round().clamp(1, 100000);

  Widget _body() {
    final rc = (1 - _ra - _rb).clamp(0.15, 0.7);
    return Row(
      children: [
        Expanded(
          flex: _flex(_col),
          child: Column(children: [
            Expanded(flex: _flex(_left), child: _module(_slots[0])),
            Expanded(flex: _flex(1 - _left), child: _module(_slots[1])),
          ]),
        ),
        Expanded(
          flex: _flex(1 - _col),
          child: Column(children: [
            Expanded(flex: _flex(_ra), child: _module(_slots[2])),
            Expanded(flex: _flex(_rb), child: _module(_slots[3])),
            Expanded(flex: _flex(rc), child: _module(_slots[4])),
          ]),
        ),
      ],
    );
  }

  // ---------- Cabeçalho ----------
  String _two(int n) => n.toString().padLeft(2, '0');
  static const _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  Color _cloudColor(String v) => v == 'SYNCED' || v == 'CONECTADO'
      ? N.green
      : v == 'ERRO'
          ? N.red
          : v == 'OFF'
              ? N.dim
              : N.amber;

  Widget _stat(String label, String value, Color c) => Text.rich(TextSpan(style: N.t(c: N.dim, s: 12), children: [
        TextSpan(text: '$label '),
        TextSpan(text: value, style: N.t(c: c, s: 12, w: FontWeight.w700)),
      ]));

  Widget _gap() => const SizedBox(width: 16);

  Widget _statusRow() {
    final ev = _nextEvent;
    final agenda = ev == null
        ? 'sem compromissos'
        : '${clip('${ev['title']}', 18)} · ${LocalCalendarService.until(ev['begin'] as DateTime)}';
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line2))),
      child: Row(
        children: [
          Text('OpenEXE', style: N.t(c: N.cyan, w: FontWeight.w700, s: 15, ls: 1)),
          _gap(),
          Icon(_online ? (_wifi ? Icons.wifi : Icons.signal_cellular_alt) : Icons.wifi_off,
              size: 16, color: _online ? N.green : N.red),
          const SizedBox(width: 4),
          Text(_online ? 'ONLINE' : 'OFFLINE',
              style: N.t(c: _online ? N.green : N.red, s: 12, w: FontWeight.w700)),
          _gap(),
          ValueListenableBuilder<int>(
            valueListenable: _power.level,
            builder: (c, v, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_power.charging ? Icons.battery_charging_full : Icons.battery_std,
                  size: 16, color: v < 20 && !_power.charging ? N.red : N.green),
              const SizedBox(width: 2),
              Text('$v%', style: N.t(s: 12, w: FontWeight.w700)),
            ]),
          ),
          if (_btOn) ...[
            const SizedBox(width: 10),
            const Icon(Icons.bluetooth, size: 16, color: _blue),
          ],
          _gap(),
          _stat('ALARME', widget.settings.alarmLabel, N.amber),
          _gap(),
          _stat('AGENDA', agenda, ev == null ? N.dim : N.amber),
          _gap(),
          ValueListenableBuilder<String>(
            valueListenable: _drive.status,
            builder: (c, v, _) =>
                _stat('DRIVE', v == 'OFF' ? 'OFF' : v, _cloudColor(v)),
          ),
          _gap(),
          _stat('AGENTE', _kit.agent.running ? 'TRABALHANDO' : 'OCIOSO',
              _kit.agent.running ? N.amber : N.dim),
          const Spacer(),
          ValueListenableBuilder<String>(
            valueListenable: _voiceStatus,
            builder: (c, v, _) => _stat('VOZ', v, v == 'PRONTA' ? N.green : N.amber),
          ),
          const SizedBox(width: 12),
          if (_update.hasUpdate) ...[
            InkWell(
              onTap: _installUpdate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    border: Border.all(color: N.amber), borderRadius: BorderRadius.circular(4)),
                child: Text(
                    _update.state == UpdateState.downloading
                        ? 'BAIXANDO ${(_update.progress * 100).round()}%'
                        : (_update.state == UpdateState.ready ? 'ATUALIZAR' : 'BAIXAR ATUALIZAÇÃO'),
                    style: N.t(c: N.amber, s: 11, w: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          InkWell(
            onTap: _openConfig,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text('CONFIG', style: N.t(c: N.dim, s: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Text('${_two(_now.hour)}:${_two(_now.minute)}', style: N.t(s: 18, w: FontWeight.w700)),
          const SizedBox(width: 8),
          Text('${_dias[_now.weekday - 1]} ${_two(_now.day)}/${_two(_now.month)}',
              style: N.t(c: N.dim, s: 12)),
        ],
      ),
    );
  }

  Widget _badged(Widget child, int n) => Stack(clipBehavior: Clip.none, children: [
        child,
        if (n > 0)
          Positioned(
            right: -2,
            top: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: N.red, borderRadius: BorderRadius.circular(9)),
              child: Text(n > 99 ? '99+' : '$n',
                  textAlign: TextAlign.center, style: N.t(c: N.bg, s: 10, w: FontWeight.w700)),
            ),
          ),
      ]);

  Widget _cmdBar() {
    Widget b(Widget w) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: w));
    final place = _kit.places.current;
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line))),
      child: Row(children: [
        b(NBtn('BUSCAR · CTRL K', onTap: _globalSearch)),
        b(NBtn('NOTA RÁPIDA', accent: true, onTap: _quickNote)),
        b(NBtn('ESCANEAR', onTap: () => _console?.ask('escanear'))),
        b(_badged(NBtn('NOTIFICAÇÕES', onTap: _showNotifications), _kit.notifs.items.length)),
        b(NBtn('AGENTE DE APPS', accent: _kit.agent.running, onTap: _showAgent)),
        b(_badged(NBtn('ROTINAS', onTap: _showRoutines), _routines.all.where((r) => r.active).length)),
        b(NBtn(_focus ? 'MODO FOCO ●' : 'MODO FOCO', accent: _focus, onTap: _toggleFocus)),
        b(NBtn('LUGAR: ${place == null ? '—' : clip(place.toUpperCase(), 9)}', onTap: _showPlace)),
      ]),
    );
  }

  // ---------- Rodapé ----------
  Widget _card(String title, Widget child,
      {VoidCallback? onTap, int flex = 10, Widget? badge}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: N.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(title,
                        style: N.t(c: N.dim, s: 10, w: FontWeight.w700, ls: 0.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                if (badge != null) badge,
              ]),
              const SizedBox(height: 4),
              Expanded(child: child),
            ]),
          ),
        ),
      ),
    );
  }

  Color _lvl(double f) => f < 0.7 ? N.green : (f < 0.85 ? N.amber : N.red);

  Widget _meter(String label, String value, double frac) {
    final f = frac.clamp(0.0, 1.0);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: N.t(c: N.dim, s: 10)),
          Text(value, style: N.t(s: 13, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: f,
              minHeight: 4,
              backgroundColor: N.line2,
              valueColor: AlwaysStoppedAnimation(_lvl(f)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _monitorCard() {
    return _card(
      'TABLET · RAM · MEMÓRIA · CPU · TEMP',
      ValueListenableBuilder<SysStats>(
        valueListenable: _monitor.stats,
        builder: (c, s, _) => Row(children: [
          _meter('RAM', '${s.ramPct}%', s.ramPct / 100),
          _meter('MEMÓRIA', '${s.storPct}%', s.storPct / 100),
          _meter('CPU', s.cpuPct < 0 ? '—' : '${s.cpuPct}%', s.cpuPct < 0 ? 0 : s.cpuPct / 100),
          _meter('TEMP', s.temp < 0 ? '—' : '${s.temp.round()}°C', s.temp < 0 ? 0 : s.temp / 80),
        ]),
      ),
      onTap: _showMonitor,
      flex: 15,
    );
  }

  Widget _tasksCard() {
    return _card(
      'TAREFAS DE HOJE',
      ValueListenableBuilder<List<TaskItem>>(
        valueListenable: _tasks.items,
        builder: (c, l, _) {
          final next = l.where((e) => !e.done).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(l.isEmpty ? 'sem tarefas' : '${_tasks.done}/${_tasks.total} feitas',
                style: N.t(s: 13, w: FontWeight.w700)),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _tasks.progress,
                minHeight: 4,
                backgroundColor: N.line2,
                valueColor: const AlwaysStoppedAnimation(N.green),
              ),
            ),
            const SizedBox(height: 3),
            Text(next.isEmpty ? (l.isEmpty ? 'toque para criar' : 'tudo feito') : 'próxima: ${next.first.text}',
                style: N.t(c: N.dim, s: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]);
        },
      ),
      onTap: _showTasks,
      flex: 10,
    );
  }

  Widget _nextCard() {
    final ev = _nextEvent;
    final b = ev == null ? null : ev['begin'] as DateTime;
    return _card(
      'PRÓXIMO COMPROMISSO',
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(ev == null ? 'nada nas próximas 24 h' : '${ev['title']}',
            style: N.t(s: 13, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(b == null ? 'toque para abrir o calendário' : '${_two(b.hour)}:${_two(b.minute)} · ${LocalCalendarService.until(b)}',
            style: N.t(c: N.amber, s: 11)),
      ]),
      onTap: () => _quick('calendar'),
      flex: 10,
    );
  }

  Widget _lastNotifCard() {
    final l = _kit.notifs.latest(n: 1);
    final n = l.isEmpty ? null : l.first;
    return _card(
      'ÚLTIMA NOTIFICAÇÃO',
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(n == null ? 'nenhuma' : n.app,
            style: N.t(s: 13, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(n == null ? 'ative em CONFIG se esperava alguma' : clip('${n.title} ${n.text}'.trim(), 60),
            style: N.t(c: N.dim, s: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
      onTap: _showNotifications,
      flex: 10,
    );
  }

  Widget _clipCard() {
    return ListenableBuilder(
      listenable: _kit.clip,
      builder: (c, _) {
        final t = _kit.clip.latest(n: 1);
        return _card(
          'ÁREA DE TRANSFERÊNCIA',
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${_kit.clip.texts.length} textos · ${_kit.clip.images.length} imagens',
                style: N.t(s: 13, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(t.isEmpty ? 'vazia' : clip(t.first.replaceAll('\n', ' '), 50),
                style: N.t(c: N.dim, s: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          badge: _kit.clip.count == 0
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: N.cyan, borderRadius: BorderRadius.circular(8)),
                  child: Text('${_kit.clip.count}', style: N.t(c: N.bg, s: 10, w: FontWeight.w700)),
                ),
          onTap: () => showClipboardPopup(context, _kit.clip),
          flex: 10,
        );
      },
    );
  }

  Widget _productivity() => Container(
        height: 84,
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: N.line))),
        child: Row(children: [
          _monitorCard(),
          _tasksCard(),
          _nextCard(),
          _lastNotifCard(),
          _clipCard(),
        ]),
      );

  Widget _footerButtons() {
    Widget b(String l, VoidCallback t, {bool accent = false}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: NBtn(l, accent: accent, onTap: t),
        );
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(children: [
        b('RELÓGIO', () => _quick('clock')),
        b('CALCULADORA', () => _quick('calculator')),
        b('CALENDÁRIO', () => _quick('calendar')),
        b('CÂMERA', () => _quick('camera')),
        b('GRAVADOR', () => _quick('recorder')),
        b('AJUSTES', () => _quick('settings')),
        const Spacer(),
        b('EDITAR LAYOUT', _editLayout, accent: true),
        b('SINCRONIZAR AGENDA', _syncAgenda),
        ListenableBuilder(
          listenable: _kbd,
          builder: (c, _) => b(_kbd.label, _toggleKeyboard, accent: _kbd.physical && !_kbd.useVirtual),
        ),
      ]),
    );
  }

  // ---------- Editar layout ----------
  Future<void> _editLayout() async {
    var col = _col, left = _left, ra = _ra, rb = _rb;
    final slots = List<int>.from(_slots);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Widget slider(String label, double v, double min, double max, ValueChanged<double> on) =>
            Row(
              children: [
                SizedBox(width: 230, child: Text(label, style: N.t(c: N.dim, s: 12))),
                Expanded(
                  child: Slider(
                    value: v.clamp(min, max),
                    min: min,
                    max: max,
                    activeColor: N.cyan,
                    onChanged: (x) => setD(() => on(x)),
                  ),
                ),
                SizedBox(width: 44, child: Text('${(v * 100).round()}%', style: N.t(s: 12))),
              ],
            );
        return Dialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 600,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Editar layout', style: N.t(c: N.cyan, w: FontWeight.w700, s: 15)),
                    const SizedBox(height: 12),
                    slider('Largura da coluna esquerda', col, 0.3, 0.7, (x) => col = x),
                    slider('Altura do módulo esquerdo de cima', left, 0.25, 0.75, (x) => left = x),
                    slider('Altura do módulo direito de cima', ra, 0.15, 0.55, (x) {
                      ra = x;
                      if (ra + rb > 0.85) rb = 0.85 - ra;
                    }),
                    slider('Altura do módulo direito do meio', rb, 0.15, 0.55, (x) {
                      rb = x;
                      if (ra + rb > 0.85) ra = 0.85 - rb;
                    }),
                    const SizedBox(height: 8),
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 230,
                                child: Text(_posNames[i], style: N.t(c: N.dim, s: 12))),
                            Expanded(
                              child: DropdownButton<int>(
                                value: slots[i],
                                isExpanded: true,
                                dropdownColor: N.field,
                                style: N.t(),
                                underline: Container(height: 1, color: N.border),
                                items: [
                                  for (var m = 0; m < 5; m++)
                                    DropdownMenuItem(value: m, child: Text(_moduleNames[m])),
                                ],
                                onChanged: (m) {
                                  if (m == null) return;
                                  setD(() {
                                    final j = slots.indexOf(m);
                                    if (j >= 0) slots[j] = slots[i];
                                    slots[i] = m;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        NBtn('Padrão', onTap: () {
                          setD(() {
                            col = 0.46;
                            left = 0.56;
                            ra = 0.36;
                            rb = 0.30;
                            slots
                              ..clear()
                              ..addAll([0, 2, 1, 4, 3]);
                          });
                        }),
                        const SizedBox(width: 8),
                        NBtn('Cancelar', onTap: () => Navigator.pop(ctx, false)),
                        const SizedBox(width: 8),
                        NBtn('Aplicar', accent: true, onTap: () => Navigator.pop(ctx, true)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );

    if (ok == true) {
      await widget.settings.setSplits5(col, left, ra, rb);
      await widget.settings.setSlots5(slots);
      setState(() {
        _col = col;
        _left = left;
        _ra = ra;
        _rb = rb;
        _slots = slots;
      });
    }
  }

  Future<void> _openConfig() async {
    if (widget.settings.lockConfig &&
        !await _kit.lock.authenticate('Abrir as configurações do OpenEXE')) {
      return;
    }
    if (!mounted) return;
    await showConfigDialog(
      context,
      settings: widget.settings,
      brain: widget.brain,
      router: _router,
      google: _google,
      drive: _drive,
      sb: _sb,
      kit: _kit,
      update: _update,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): _globalSearch,
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): _quickNote,
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => _console?.showKeyboard(),
          const SingleActivator(LogicalKeyboardKey.keyM, control: true): () => _console?.toggleMic(),
          const SingleActivator(LogicalKeyboardKey.escape): () => _console?.clearInput(),
          const SingleActivator(LogicalKeyboardKey.f1): () => _console?.ask('ajuda'),
        },
        child: Scaffold(
          backgroundColor: N.bg,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: Column(
              children: [
                _statusRow(),
                _cmdBar(),
                Expanded(child: _body()),
                _productivity(),
                _footerButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
