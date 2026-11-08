import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'settings_store.dart';
import 'text_utils.dart';

/// Dono único do reconhecimento de voz. O console, a confirmação por voz ("sim", "pode")
/// e a palavra de ativação dividem o mesmo microfone por aqui, sem brigar.
class VoiceService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  bool listening = false;
  String owner = '';
  void Function()? _onEnd;

  Future<bool> _init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') _ended();
      },
      onError: (_) => _ended(),
    );
    return _ready;
  }

  void _ended() {
    if (!listening) return;
    listening = false;
    final cb = _onEnd;
    _onEnd = null;
    notifyListeners();
    cb?.call();
  }

  /// Escuta uma vez. [onResult] recebe o texto e se é o resultado final.
  Future<bool> listen({
    required String owner,
    required void Function(String text, bool isFinal) onResult,
    void Function()? onEnd,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 4),
  }) async {
    if (!await _init()) return false;
    if (listening) await stop();
    listening = true;
    this.owner = owner;
    _onEnd = onEnd;
    notifyListeners();
    try {
      await _stt.listen(
        localeId: 'pt_BR',
        listenFor: listenFor,
        pauseFor: pauseFor,
        onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      );
    } catch (_) {
      listening = false;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
    if (listening) {
      listening = false;
      _onEnd = null;
      notifyListeners();
    }
  }

  static final _yes = RegExp(r'\b(sim|pode|confirmo|confirma|autorizo|isso|vai|claro|ok)\b');
  static final _no = RegExp(r'\b(nao|cancela|cancelar|para|parar|nunca|negativo)\b');

  /// Ouve "sim" ou "não". Devolve true/false, ou null se não entendeu ou acabou o tempo.
  Future<bool?> yesNo({Duration wait = const Duration(seconds: 20)}) async {
    final c = Completer<bool?>();
    final ok = await listen(
      owner: 'confirm',
      listenFor: wait,
      pauseFor: const Duration(seconds: 3),
      onResult: (t, fin) {
        final n = norm(t);
        if (c.isCompleted) return;
        if (_no.hasMatch(n)) {
          c.complete(false);
        } else if (_yes.hasMatch(n)) {
          c.complete(true);
        }
      },
      onEnd: () {
        if (!c.isCompleted) c.complete(null);
      },
    );
    if (!ok) return null;
    final r = await c.future;
    if (owner == 'confirm') await stop();
    return r;
  }
}

/// Palavra de ativação: com o OpenEXE aberto, escuta em ciclos curtos e reage quando você
/// fala uma das palavras seguida de um pedido ("ei exe, abre o WhatsApp"). Só a frase final
/// é analisada; o áudio passa pelo reconhecimento de voz do Android (o mesmo do MIC).
/// Custo: gasta bateria e o Android pode tocar um sinal a cada ciclo de escuta.
class WakeWordService {
  WakeWordService(this.voice, this.settings, this.onCommand, this.onWakeOnly);
  final VoiceService voice;
  final SettingsStore settings;

  /// Pedido falado depois da palavra de ativação.
  final void Function(String command) onCommand;

  /// Só a palavra, sem pedido: abra o microfone normal.
  final void Function() onWakeOnly;

  bool _on = false;
  Timer? _t;

  bool get running => _on;

  void start() {
    if (_on) return;
    _on = true;
    _schedule(const Duration(milliseconds: 500));
  }

  void stop() {
    _on = false;
    _t?.cancel();
    if (voice.listening && voice.owner == 'wake') voice.stop();
  }

  void _schedule(Duration d) {
    _t?.cancel();
    if (!_on) return;
    _t = Timer(d, _loop);
  }

  List<String> get _words => settings.wakeWords
      .split(',')
      .map((e) => norm(e.trim()))
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _loop() async {
    if (!_on) return;
    if (voice.listening) {
      _schedule(const Duration(seconds: 3));
      return;
    }
    final words = _words;
    if (words.isEmpty) return;
    final ok = await voice.listen(
      owner: 'wake',
      listenFor: const Duration(seconds: 25),
      pauseFor: const Duration(seconds: 3),
      onResult: (t, fin) {
        if (!fin || !_on) return;
        final n = norm(t);
        for (final w in words) {
          final i = n.indexOf(w);
          if (i < 0) continue;
          final rest = n.substring(i + w.length).replaceFirst(RegExp(r'^[ ,.:;!-]+'), '').trim();
          if (rest.length >= 3) {
            onCommand(rest);
          } else {
            onWakeOnly();
          }
          return;
        }
      },
      onEnd: () => _schedule(const Duration(milliseconds: 1500)),
    );
    if (!ok) _schedule(const Duration(seconds: 15));
  }
}
