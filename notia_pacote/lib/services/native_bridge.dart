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
  static Future<bool> confirmOverlay(String msg) async {
    final f = events
        .firstWhere((e) => e['type'] == 'agent_confirm')
        .timeout(const Duration(seconds: 60), onTimeout: () => <String, dynamic>{'ok': false});
    await _call<void>('a11y.confirm', {'text': msg});
    final e = await f;
    return e['ok'] == true;
  }

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
}
