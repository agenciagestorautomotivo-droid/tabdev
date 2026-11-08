import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'native_bridge.dart';
import 'settings_store.dart';

/// Identificador desta versão. O GitHub Actions injeta o hash do commit com
/// --dart-define=BUILD_ID=...; fora disso vale "dev" (nunca se atualiza sozinho).
const kBuildId = String.fromEnvironment('BUILD_ID', defaultValue: 'dev');

enum UpdateState { idle, checking, upToDate, available, downloading, ready, error }

/// Atualização automática: procura um APK novo nos Releases do GitHub (tag apk-latest),
/// baixa em segundo plano (só no Wi-Fi, se o modo automático estiver ligado) e deixa
/// pronto para instalar. O Android sempre exige um toque seu para confirmar a instalação.
/// Repositório privado: usa o token do GitHub da CONFIG (precisa de leitura em "Contents").
class UpdateService extends ChangeNotifier {
  UpdateService(this.settings);
  final SettingsStore settings;

  UpdateState state = UpdateState.idle;
  String message = '';
  double progress = 0;
  String remoteBuild = '';
  String? _assetUrl;
  Timer? _timer;

  bool get hasUpdate => state == UpdateState.available || state == UpdateState.ready || state == UpdateState.downloading;
  String get currentBuild => kBuildId == 'dev' ? 'dev' : kBuildId.substring(0, 7);

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check(wifi: _wifi));
  }

  bool _wifi = true;
  void setWifi(bool v) => _wifi = v;

  void disposeTimer() => _timer?.cancel();

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        if (settings.ghToken.isNotEmpty) 'Authorization': 'Bearer ${settings.ghToken}',
      };

  void _set(UpdateState s, [String m = '']) {
    state = s;
    message = m;
    notifyListeners();
  }

  /// Procura versão nova. Se [auto] e o modo automático estiver ligado (e houver Wi-Fi), já baixa.
  Future<void> check({bool wifi = true, bool auto = true}) async {
    if (state == UpdateState.checking || state == UpdateState.downloading) return;
    _set(UpdateState.checking, 'Procurando atualização…');
    try {
      final r = await http
          .get(Uri.parse('https://api.github.com/repos/${settings.updateRepo}/releases/tags/apk-latest'),
              headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 404) {
        _set(UpdateState.error,
            settings.ghToken.isEmpty
                ? 'Não achei o release. Se o repositório é privado, coloque o token do GitHub em CONFIG.'
                : 'Release não encontrado. Confira o repositório e o token.');
        return;
      }
      if (r.statusCode != 200) {
        _set(UpdateState.error, 'GitHub respondeu ${r.statusCode}.');
        return;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final body = '${j['body'] ?? ''}';
      final m = RegExp(r'build:([0-9a-f]{40})').firstMatch(body);
      remoteBuild = m?.group(1) ?? '';
      final assets = (j['assets'] as List?) ?? [];
      final apk = assets.cast<Map>().where((a) => '${a['name']}'.endsWith('.apk')).toList();
      if (remoteBuild.isEmpty || apk.isEmpty) {
        _set(UpdateState.error, 'O release não tem um APK válido.');
        return;
      }
      _assetUrl = '${apk.first['url']}';
      if (kBuildId == 'dev' || remoteBuild == kBuildId) {
        _set(UpdateState.upToDate, kBuildId == 'dev' ? 'Versão de teste (sem número).' : 'Você está na versão mais recente.');
        return;
      }
      if (settings.downloadedBuild == remoteBuild && await _file() != null) {
        _set(UpdateState.ready, 'Atualização pronta para instalar.');
        return;
      }
      _set(UpdateState.available, 'Há uma atualização (${remoteBuild.substring(0, 7)}).');
      if (auto && settings.autoUpdate && wifi) await download();
    } catch (e) {
      _set(UpdateState.error, 'Sem conexão para verificar.');
    }
  }

  Future<String?> _file() async {
    final d = await NativeBridge.updateDir();
    if (d == null) return null;
    final f = File('$d/OpenEXE.apk');
    return await f.exists() && await f.length() > 1000000 ? f.path : null;
  }

  Future<void> download() async {
    final url = _assetUrl;
    final dir = await NativeBridge.updateDir();
    if (url == null || dir == null) return;
    _set(UpdateState.downloading, 'Baixando atualização…');
    progress = 0;
    final tmp = File('$dir/OpenEXE.part');
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers.addAll({..._headers, 'Accept': 'application/octet-stream'});
      final res = await http.Client().send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        _set(UpdateState.error, 'Falha ao baixar (${res.statusCode}).');
        return;
      }
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = tmp.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          final p = got / total;
          if (p - progress > 0.02) {
            progress = p;
            notifyListeners();
          }
        }
      }
      await sink.close();
      final dest = File('$dir/OpenEXE.apk');
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
      await settings.setDownloadedBuild(remoteBuild);
      _set(UpdateState.ready, 'Atualização pronta para instalar.');
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      _set(UpdateState.error, 'O download falhou. Tente de novo no Wi-Fi.');
    }
  }

  /// Abre o instalador. Se faltar a permissão, o Android abre a tela para liberar.
  Future<String> install() async {
    final f = await _file();
    if (f == null) {
      _set(UpdateState.error, 'Arquivo da atualização não encontrado. Baixe de novo.');
      return 'erro';
    }
    return NativeBridge.installApk(f);
  }
}
