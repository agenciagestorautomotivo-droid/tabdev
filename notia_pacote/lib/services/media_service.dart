import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'settings_store.dart';
import 'vault_service.dart';

class MediaResult {
  MediaResult(this.path, this.kind);
  final String path;
  final String kind; // 'image' ou 'music'
}

/// Geração de mídia por IA. Tudo é salvo em Midia/ dentro do Vault (e entra no backup do Drive).
/// Imagem: Pollinations (grátis, sem chave). Música: MusicGen no Hugging Face (token grátis).
class MediaService {
  MediaService(this.settings, this.vault);
  final SettingsStore settings;
  final VaultService vault;

  /// Traduz o pedido de música para inglês (o MusicGen entende melhor). Ligado pelo shell.
  Future<String> Function(String text)? translator;

  Future<Directory> _dir(String sub) async {
    String base;
    if (await vault.ensure()) {
      base = '${VaultService.root}/Midia';
    } else {
      base = '${(await getApplicationDocumentsDirectory()).path}/Midia';
    }
    final d = Directory('$base/$sub');
    await d.create(recursive: true);
    return d;
  }

  String _file(String prompt, String ext) {
    final s = vault.slug(prompt);
    return '${DateTime.now().millisecondsSinceEpoch}-${s.substring(0, math.min(30, s.length))}.$ext';
  }

  Future<MediaResult> image(String prompt) async {
    final seed = math.Random().nextInt(1 << 20);
    final uri = Uri.parse(
        'https://image.pollinations.ai/prompt/${Uri.encodeComponent(prompt)}?width=1024&height=768&nologo=true&seed=$seed');
    final res = await http.get(uri).timeout(const Duration(seconds: 90));
    final ct = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || !ct.startsWith('image/') || res.bodyBytes.length < 1000) {
      throw Exception('o serviço de imagem não respondeu (${res.statusCode})');
    }
    final f = File('${(await _dir('Imagens')).path}/${_file(prompt, 'jpg')}');
    await f.writeAsBytes(res.bodyBytes);
    return MediaResult(f.path, 'image');
  }

  Future<MediaResult> music(String prompt) async {
    if (settings.hfToken.isEmpty) {
      throw Exception('falta o token do Hugging Face em CONFIG (grátis)');
    }
    var text = prompt;
    try {
      final t = translator;
      if (t != null) text = (await t(prompt)).trim();
      if (text.isEmpty) text = prompt;
    } catch (_) {
      text = prompt;
    }
    final res = await http
        .post(
          Uri.parse('https://api-inference.huggingface.co/models/facebook/musicgen-small'),
          headers: {
            'Authorization': 'Bearer ${settings.hfToken}',
            'Content-Type': 'application/json',
            'x-wait-for-model': 'true',
          },
          body: jsonEncode({'inputs': text}),
        )
        .timeout(const Duration(seconds: 150));
    final ct = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || ct.contains('json') || res.bodyBytes.length < 2000) {
      throw Exception('o serviço de música respondeu ${res.statusCode}');
    }
    final ext = ct.contains('flac')
        ? 'flac'
        : ct.contains('mpeg')
            ? 'mp3'
            : ct.contains('ogg')
                ? 'ogg'
                : 'wav';
    final f = File('${(await _dir('Musicas')).path}/${_file(prompt, ext)}');
    await f.writeAsBytes(res.bodyBytes);
    return MediaResult(f.path, 'music');
  }

  /// Criações salvas (imagens e músicas), mais novas primeiro.
  Future<List<MediaResult>> library() async {
    final out = <File, String>{};
    for (final sub in ['Imagens', 'Musicas']) {
      final d = await _dir(sub);
      await for (final e in d.list()) {
        if (e is File) out[e] = sub == 'Imagens' ? 'image' : 'music';
      }
    }
    final files = out.keys.toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return [for (final f in files) MediaResult(f.path, out[f]!)];
  }
}
