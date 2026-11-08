import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Um elemento da tela de outro app, como o serviço de acessibilidade o enxerga.
class ScreenNode {
  ScreenNode(this.id, this.kind, this.text,
      {this.scrollable = false, this.checked, this.password = false});
  final int id;
  final String kind; // btn, txt, input, check, img
  final String text;
  final bool scrollable;
  final bool? checked;
  final bool password;
}

class ScreenSnapshot {
  ScreenSnapshot(this.pkg, this.nodes);
  final String pkg;
  final List<ScreenNode> nodes;

  ScreenNode? byId(int id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Texto compacto para a IA: uma linha por elemento ("id:tipo:texto").
  String toPrompt() {
    final b = StringBuffer();
    for (final n in nodes) {
      b.write('${n.id}:${n.kind}');
      if (n.scrollable) b.write('*');
      if (n.checked != null) b.write(n.checked! ? ':ligado' : ':desligado');
      if (n.password) b.write(':senha');
      if (n.text.isNotEmpty) b.write(':${n.text}');
      b.writeln();
    }
    return b.toString();
  }

  String get fingerprint => nodes.map((n) => '${n.kind}${n.text}${n.checked}').join('|');
}

/// Ponte com o lado Android (Kotlin): acessibilidade, notificações, calendário,
/// telas de configuração e eventos (notificações, compartilhar, atalho, parar).
class NativeBridge {
  static const _m = MethodChannel('notia/system');
  static const _e = EventChannel('notia/events');

  static Stream<Map<String, dynamic>>? _events;
  static Stream<Map<String, dynamic>> get events => _events ??= _e
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map))
      .asBroadcastStream();

  static Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _m.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  // ----- Acessibilidade -----
  static Future<bool> a11yEnabled() async => (await _call<bool>('a11y.enabled')) ?? false;

  static Future<ScreenSnapshot?> snapshot() async {
    final raw = await _call<String>('a11y.snapshot');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final nodes = <ScreenNode>[];
      for (final o in (j['nodes'] as List)) {
        final m = o as Map<String, dynamic>;
        nodes.add(ScreenNode(
          m['i'] as int,
          m['k'] as String,
          (m['x'] as String?) ?? '',
          scrollable: m['s'] == 1,
          checked: m.containsKey('on') ? m['on'] == 1 : null,
          password: m['pw'] == 1,
        ));
      }
      return ScreenSnapshot((j['pkg'] as String?) ?? '', nodes);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> click(int index) async =>
      (await _call<bool>('a11y.click', {'index': index})) ?? false;
  static Future<bool> setText(int index, String text) async =>
      (await _call<bool>('a11y.setText', {'index': index, 'text': text})) ?? false;
  static Future<bool> scroll(bool down) async =>
      (await _call<bool>('a11y.scroll', {'down': down})) ?? false;
  static Future<bool> back() async => (await _call<bool>('a11y.back')) ?? false;
  static Future<bool> home() async => (await _call<bool>('a11y.home')) ?? false;
  static Future<void> overlay(String text, {bool show = true}) =>
      _call<void>('a11y.overlay', {'text': text, 'show': show});

  /// Pergunta SIM/NÃO por cima do app em uso e espera a resposta (60 s; sem resposta = não).
  /// Ligado pelo shell: ouve "sim"/"não" pelo microfone (null = não entendeu).
  static Future<bool?> Function()? voiceConfirm;
  static Future<void> Function()? voiceStop;

  static Future<bool> confirmOverlay(String msg) async {
    final f = events
        .firstWhere((e) => e['type'] == 'agent_confirm')
        .timeout(const Duration(seconds: 60), onTimeout: () => <String, dynamic>{'ok': false});
    await _call<void>('a11y.confirm', {'text': msg});
    final vc = voiceConfirm;
    if (vc == null) return (await f)['ok'] == true;
    // Toque no SIM/NÃO ou resposta falada: vale o que vier primeiro.
    final c = Completer<bool>();
    var byVoice = false;
    f.then((e) {
      if (!c.isCompleted) c.complete(e['ok'] == true);
    });
    vc().then((v) {
      if (v != null && !c.isCompleted) {
        byVoice = true;
        c.complete(v);
      }
    });
    final r = await c.future;
    await voiceStop?.call();
    if (byVoice) await _call<void>('a11y.hideConfirm');
    return r;
  }

  // ----- Despertador, segundo plano -----
  static Future<bool> setAlarm(int hour, int minute, String label) async =>
      (await _call<bool>('alarm.set', {'hour': hour, 'minute': minute, 'label': label})) ?? false;

  /// Próximo alarme do relógio do sistema, ou null.
  static Future<DateTime?> nextAlarm() async {
    final ms = await _call<int>('alarm.next');
    return ms == null || ms <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<bool> keepAlive(bool on) async =>
      (await _call<bool>('keepalive', {'on': on})) ?? false;

  // ----- Notificações -----
  static Future<bool> notifEnabled() async => (await _call<bool>('notif.enabled')) ?? false;

  static Future<List<Map<String, dynamic>>> recentNotifications({int limit = 50}) async {
    final l = await _call<List<dynamic>>('notif.recent', {'limit': limit});
    if (l == null) return [];
    return [for (final e in l) Map<String, dynamic>.from(e as Map)];
  }

  static Future<void> clearNotifications() => _call<void>('notif.clear');

  // ----- Calendário do aparelho -----
  static Future<List<Map<String, dynamic>>?> calendarEvents(DateTime from, DateTime to) async {
    final l = await _call<List<dynamic>>('calendar.events', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    if (l == null) return null;
    return [for (final e in l) Map<String, dynamic>.from(e as Map)];
  }

  // ----- Telas de configuração do Android -----
  /// which: accessibility, notifications, appdetails, battery
  static Future<void> openSettings(String which) => _call<bool>('openSettings', {'which': which});

  // ----- Painel do aparelho (OpenEXE) -----
  static Future<Map<String, dynamic>?> sysStats() async {
    final m = await _call<Map<dynamic, dynamic>>('sys.stats');
    return m == null ? null : Map<String, dynamic>.from(m);
  }

  // ----- Termux (TAB DEV-IA) -----
  static Future<Map<String, dynamic>> termuxState() async {
    final m = await _call<Map<dynamic, dynamic>>('termux.state');
    return m == null ? {} : Map<String, dynamic>.from(m);
  }

  static Future<void> termuxPerm() => _call<bool>('termux.perm');
  static Future<bool> termuxOpen() async => (await _call<bool>('termux.open')) ?? false;
  static Future<String> termuxRun(String id, String cmd) async =>
      (await _call<String>('termux.run', {'id': id, 'cmd': cmd})) ?? 'erro:sem_resposta';

  static Future<Map<String, dynamic>> secInfo() async {
    final m = await _call<Map<dynamic, dynamic>>('sec.info');
    return m == null ? {} : Map<String, dynamic>.from(m);
  }

  static Future<Map<String, dynamic>> optInfo() async {
    final m = await _call<Map<dynamic, dynamic>>('opt.info');
    return m == null ? {} : Map<String, dynamic>.from(m);
  }

  /// Apaga o cache do app e devolve os bytes liberados.
  static Future<int> clearCache() async => (await _call<int>('opt.clearCache')) ?? 0;

  static Future<bool> bluetoothOn() async => (await _call<bool>('sys.bluetooth')) ?? false;
  static Future<bool> physicalKeyboard() async => (await _call<bool>('sys.keyboard')) ?? false;

  /// which: clock, calculator, calendar, camera, recorder, settings
  static Future<bool> quickApp(String which) async =>
      (await _call<bool>('app.quick', {'which': which})) ?? false;
  static Future<bool> uninstall(String pkg) async =>
      (await _call<bool>('app.uninstall', {'pkg': pkg})) ?? false;
  static Future<bool> appInfo(String pkg) async =>
      (await _call<bool>('app.info', {'pkg': pkg})) ?? false;

  /// Imagem na área de transferência (copiada para a pasta do app) ou null.
  static Future<Map<String, dynamic>?> clipImage() async {
    final m = await _call<Map<dynamic, dynamic>>('clip.image');
    return m == null ? null : Map<String, dynamic>.from(m);
  }

  static Future<bool> setClipImage(String path) async =>
      (await _call<bool>('clip.setImage', {'path': path})) ?? false;

  // ----- Atualização e launcher -----
  static Future<String?> updateDir() => _call<String>('update.dir');

  /// "ok", "permissao" (abriu a tela para liberar) ou "erro".
  static Future<String> installApk(String path) async =>
      (await _call<String>('update.install', {'path': path})) ?? 'erro';

  /// Abre a tela do Android para escolher o launcher padrão.
  static Future<bool> homeSettings() async => (await _call<bool>('sys.homeSettings')) ?? false;
}
