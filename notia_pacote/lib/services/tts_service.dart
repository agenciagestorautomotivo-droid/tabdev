import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'settings_store.dart';

/// Voz do assistente: voz do tablet (instantânea, offline, grátis) ou Gemini TTS (mais natural,
/// mas com limite no plano grátis). Se o Gemini falhar, cai sozinho na voz do tablet.
class TtsService extends ChangeNotifier {
  TtsService(this.settings);
  final SettingsStore settings;
  final FlutterTts _sys = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  bool speaking = false;
  bool _ready = false;
  int _gen = 0;
  DateTime _geminiBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Último aviso útil (ex.: "Gemini no limite, usei a voz do tablet").
  String lastNote = '';

  static const geminiVoices = [
    'Kore', 'Puck', 'Zephyr', 'Charon', 'Fenrir', 'Leda', 'Orus', 'Aoede', 'Callirrhoe', 'Autonoe',
    'Enceladus', 'Iapetus', 'Umbriel', 'Algieba', 'Despina', 'Erinome', 'Algenib', 'Rasalgethi',
    'Laomedeia', 'Achernar', 'Alnilam', 'Schedar', 'Gacrux', 'Pulcherrima', 'Achird',
    'Zubenelgenubi', 'Vindemiatrix', 'Sadachbia', 'Sadaltager', 'Sulafat',
  ];

  Future<void> _setup() async {
    await _sys.setLanguage('pt-BR');
    await _sys.awaitSpeakCompletion(true);
    await _applySystem();
    _sys.setStartHandler(() {
      speaking = true;
      notifyListeners();
    });
    _sys.setCompletionHandler(_done);
    _sys.setCancelHandler(_done);
    _sys.setErrorHandler((_) => _done());
    _ready = true;
  }

  void _done() {
    if (_player.state == PlayerState.playing) return;
    if (speaking) {
      speaking = false;
      notifyListeners();
    }
  }

  /// Reaplica velocidade, tom, volume e voz escolhidos.
  Future<void> _applySystem() async {
    // flutter_tts no Android: 0.5 = velocidade normal, 1.0 = o dobro.
    await _sys.setSpeechRate((settings.ttsRate * 0.5).clamp(0.1, 1.0));
    await _sys.setPitch(settings.ttsPitch);
    await _sys.setVolume(settings.ttsVolume);
    final v = settings.ttsVoice;
    if (v.isNotEmpty) {
      final loc = settings.ttsVoiceLocale;
      await _sys.setVoice({'name': v, 'locale': loc.isEmpty ? 'pt-BR' : loc});
    }
  }

  Future<void> refresh() async {
    if (!_ready) await _setup();
    await _applySystem();
  }

  /// Vozes em português instaladas no tablet: [{name, locale}].
  Future<List<Map<String, String>>> systemVoices() async {
    if (!_ready) await _setup();
    try {
      final l = await _sys.getVoices as List? ?? [];
      final out = <Map<String, String>>[];
      for (final e in l) {
        final m = Map<String, dynamic>.from(e as Map);
        final loc = '${m['locale'] ?? ''}';
        if (loc.toLowerCase().startsWith('pt')) out.add({'name': '${m['name']}', 'locale': loc});
      }
      out.sort((a, b) => a['name']!.compareTo(b['name']!));
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> stop() async {
    _gen++;
    try {
      await _sys.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    if (speaking) {
      speaking = false;
      notifyListeners();
    }
  }

  /// Limpa marcações para a voz não ler símbolos.
  static String clean(String t) => t
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' trecho de código ')
      .replaceAll(RegExp(r'https?://\S+'), ' link ')
      .replaceAll(RegExp(r'[*_`#>~|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> speak(String raw) async {
    final text = clean(raw);
    if (text.isEmpty) return;
    if (!_ready) await _setup();
    await stop();
    final my = _gen;
    speaking = true;
    notifyListeners();
    final useGemini = settings.ttsEngine == 'gemini' &&
        settings.geminiKey.isNotEmpty &&
        text.length <= 900 &&
        DateTime.now().isAfter(_geminiBlockedUntil);
    if (useGemini) {
      final ok = await _speakGemini(text, my);
      if (ok || my != _gen) return;
    }
    if (my != _gen) return;
    await _applySystem();
    await _sys.speak(text);
  }

  // ---------- Gemini TTS ----------
  Future<String?> _ttsModel() async {
    final saved = settings.geminiTtsModel;
    if (saved.isNotEmpty) return saved;
    return _discover();
  }

  Future<String?> _discover() async {
    try {
      final r = await http.get(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200'),
          headers: {'x-goog-api-key': settings.geminiKey}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      String? best;
      double bs = -1;
      for (final m in (jsonDecode(utf8.decode(r.bodyBytes))['models'] as List? ?? [])) {
        final name = ('${m['name']}').replaceFirst('models/', '');
        final methods = (m['supportedGenerationMethods'] as List? ?? []).map((e) => '$e').toList();
        if (!name.contains('tts') || !methods.contains('generateContent')) continue;
        final v = double.tryParse(RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(name)?.group(1) ?? '') ?? 0;
        var sc = v * 10;
        if (name.contains('flash')) sc += 3;
        if (name.contains('lite')) sc -= 1;
        if (name.contains('pro')) sc -= 4;
        if (name.contains('preview')) sc -= 0.5;
        if (sc > bs) {
          bs = sc;
          best = name;
        }
      }
      if (best != null) await settings.setGeminiTtsModel(best);
      return best;
    } catch (_) {
      return null;
    }
  }

  Uint8List _wav(Uint8List pcm, {int rate = 24000}) {
    final b = BytesBuilder();
    void i32(int v) => b.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
    void i16(int v) => b.add([v & 255, (v >> 8) & 255]);
    b.add(ascii.encode('RIFF'));
    i32(36 + pcm.length);
    b.add(ascii.encode('WAVEfmt '));
    i32(16);
    i16(1);
    i16(1);
    i32(rate);
    i32(rate * 2);
    i16(2);
    i16(16);
    b.add(ascii.encode('data'));
    i32(pcm.length);
    b.add(pcm);
    return b.toBytes();
  }

  /// Devolve true se falou pelo Gemini. Qualquer falha devolve false (cai na voz do tablet).
  Future<bool> _speakGemini(String text, int my, {bool retry = true}) async {
    try {
      final model = await _ttsModel();
      if (model == null) {
        lastNote = 'Gemini sem modelo de voz disponível; usei a voz do tablet.';
        return false;
      }
      final r = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
            headers: {'x-goog-api-key': settings.geminiKey, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': 'Leia em português do Brasil, em tom natural e simpático: $text'}
                  ]
                }
              ],
              'generationConfig': {
                'responseModalities': ['AUDIO'],
                'speechConfig': {
                  'voiceConfig': {
                    'prebuiltVoiceConfig': {'voiceName': settings.geminiVoice}
                  }
                }
              },
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 404 && retry) {
        await settings.setGeminiTtsModel('');
        return _speakGemini(text, my, retry: false);
      }
      if (r.statusCode == 429) {
        _geminiBlockedUntil = DateTime.now().add(const Duration(minutes: 2));
        lastNote = 'Limite grátis do Gemini atingido; voz do tablet por 2 min.';
        return false;
      }
      if (r.statusCode != 200) {
        lastNote = 'Gemini voz HTTP ${r.statusCode}; usei a voz do tablet.';
        return false;
      }
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      final b64 = data['candidates'][0]['content']['parts'][0]['inlineData']['data'] as String;
      if (my != _gen) return true;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav');
      await f.writeAsBytes(_wav(base64Decode(b64)));
      if (my != _gen) return true;
      await _player.setPlaybackRate(settings.geminiRate);
      await _player.play(DeviceFileSource(f.path));
      await _player.onPlayerComplete.first.timeout(const Duration(minutes: 3), onTimeout: () {});
      try {
        await f.delete();
      } catch (_) {}
      if (my == _gen && speaking) {
        speaking = false;
        notifyListeners();
      }
      lastNote = '';
      return true;
    } catch (e) {
      lastNote = 'Gemini voz falhou; usei a voz do tablet.';
      return false;
    }
  }

  @override
  void dispose() {
    _sys.stop();
    _player.dispose();
    super.dispose();
  }
}
