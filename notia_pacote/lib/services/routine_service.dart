import 'dart:async';
import 'dart:convert';

import 'settings_store.dart';
import 'text_utils.dart';

class RItem {
  RItem(this.text, {this.done = false});
  String text;
  bool done;
  Map<String, dynamic> toJson() => {'t': text, 'd': done};
  static RItem fromJson(Map<String, dynamic> j) => RItem('${j['t']}', done: j['d'] == true);
}

class Routine {
  Routine(this.trigger, this.command,
      {this.active = true, this.lastRunMs = 0, List<RItem>? checklist, List<RItem>? steps})
      : checklist = checklist ?? [],
        steps = steps ?? [];
  final String trigger; // hora:07:00 | carregador | bateria<20 | local:casa | notif:whatsapp
  final String command; // qualquer comando do console
  bool active;
  int lastRunMs;

  /// Checklist (itens independentes) e linha do tempo (etapas em ordem; a primeira
  /// não concluída é a etapa atual).
  final List<RItem> checklist;
  final List<RItem> steps;

  bool get manual => trigger == 'manual';
  int get checksDone => checklist.where((e) => e.done).length;

  /// Índice da etapa atual, ou -1 se todas concluídas / sem etapas.
  int get currentStep => steps.indexWhere((e) => !e.done);

  Map<String, dynamic> toJson() => {
        't': trigger,
        'c': command,
        'a': active,
        'l': lastRunMs,
        'cl': [for (final e in checklist) e.toJson()],
        'st': [for (final e in steps) e.toJson()],
      };
  static Routine fromJson(Map<String, dynamic> j) => Routine('${j['t']}', '${j['c']}',
      active: j['a'] != false,
      lastRunMs: (j['l'] as num?)?.toInt() ?? 0,
      checklist: [for (final e in (j['cl'] as List? ?? [])) RItem.fromJson(Map<String, dynamic>.from(e as Map))],
      steps: [for (final e in (j['st'] as List? ?? [])) RItem.fromJson(Map<String, dynamic>.from(e as Map))]);

  String get label {
    if (manual) return 'tarefa manual';
    if (trigger.startsWith('hora:')) return 'às ${trigger.substring(5)}';
    if (trigger == 'carregador') return 'ao ligar o carregador';
    if (trigger.startsWith('bateria<')) return 'bateria abaixo de ${trigger.substring(8)}%';
    if (trigger.startsWith('local:')) return 'ao chegar em ${trigger.substring(6)}';
    if (trigger.startsWith('notif:')) return 'ao chegar notificação de ${trigger.substring(6)}';
    return trigger;
  }
}

/// Rotinas: "às 07:00, resumir minha agenda", "ao ligar o carregador, drive: backup".
/// Rodam enquanto o Notia está aberto (ele é o launcher, então quase sempre está).
/// Horários perdidos nos últimos 90 minutos são executados quando o app volta.
class RoutineService {
  RoutineService(this.settings) {
    try {
      final l = jsonDecode(settings.routinesJson) as List;
      _list = [for (final e in l) Routine.fromJson(Map<String, dynamic>.from(e as Map))];
    } catch (_) {
      _list = [];
    }
  }
  final SettingsStore settings;
  late List<Routine> _list;
  Timer? _timer;

  /// Quem executa o comando (o console do Notia).
  Future<void> Function(String command, String why)? runner;

  List<Routine> get all => List.unmodifiable(_list);

  Future<void> _save() => settings.setRoutinesJson(jsonEncode(_list.map((e) => e.toJson()).toList()));

  /// Entende: "07:00 resumir agenda", "carregador => drive: backup", "local casa => ...",
  /// "notif whatsapp => resumir notificações", "bateria<20 => ...".
  Routine? parse(String input) {
    var s = input.trim();
    String? cmd;
    final arrow = s.indexOf('=>');
    String head = s;
    if (arrow > 0) {
      head = s.substring(0, arrow).trim();
      cmd = s.substring(arrow + 2).trim();
    }
    final words = head.split(RegExp(r'\s+'));
    String? trig;
    var used = 0;
    final t = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(words.first);
    if (t != null) {
      final h = int.parse(t.group(1)!), m = int.parse(t.group(2)!);
      if (h > 23 || m > 59) return null;
      trig = 'hora:${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      used = 1;
    } else if (norm(words.first) == 'carregador') {
      trig = 'carregador';
      used = 1;
    } else if (RegExp(r'^bateria<(\d{1,2})$').hasMatch(words.first)) {
      trig = words.first;
      used = 1;
    } else if (words.length >= 2 && (norm(words.first) == 'local' || norm(words.first) == 'notif')) {
      trig = '${norm(words.first)}:${norm(words[1])}';
      used = 2;
    }
    if (trig == null) return null;
    cmd ??= words.skip(used).join(' ');
    if (cmd.isEmpty) return null;
    return Routine(trig, cmd);
  }

  Future<void> add(Routine r) async {
    // Uma rotina nova só vale daqui para frente (não dispara um horário que já passou hoje).
    if (r.lastRunMs == 0) r.lastRunMs = DateTime.now().millisecondsSinceEpoch;
    _list.add(r);
    await _save();
  }

  Future<bool> removeAt(int i) async {
    if (i < 0 || i >= _list.length) return false;
    _list.removeAt(i);
    await _save();
    return true;
  }

  Future<void> toggle(int i) async {
    if (i < 0 || i >= _list.length) return;
    _list[i].active = !_list[i].active;
    await _save();
  }

  bool _ok(int i) => i >= 0 && i < _list.length;

  Future<void> addCheck(int i, String t) async {
    if (!_ok(i) || t.trim().isEmpty) return;
    _list[i].checklist.add(RItem(t.trim()));
    await _save();
  }

  Future<void> toggleCheck(int i, int j) async {
    if (!_ok(i) || j >= _list[i].checklist.length) return;
    _list[i].checklist[j].done = !_list[i].checklist[j].done;
    await _save();
  }

  Future<void> removeCheck(int i, int j) async {
    if (!_ok(i) || j >= _list[i].checklist.length) return;
    _list[i].checklist.removeAt(j);
    await _save();
  }

  Future<void> addStep(int i, String t) async {
    if (!_ok(i) || t.trim().isEmpty) return;
    _list[i].steps.add(RItem(t.trim()));
    await _save();
  }

  /// Conclui (ou reabre) uma etapa da linha do tempo.
  Future<void> toggleStep(int i, int j) async {
    if (!_ok(i) || j >= _list[i].steps.length) return;
    _list[i].steps[j].done = !_list[i].steps[j].done;
    await _save();
  }

  Future<void> removeStep(int i, int j) async {
    if (!_ok(i) || j >= _list[i].steps.length) return;
    _list[i].steps.removeAt(j);
    await _save();
  }

  Future<void> clearSteps(int i) async {
    if (!_ok(i)) return;
    _list[i].steps.clear();
    await _save();
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    tick();
  }

  void dispose() => _timer?.cancel();

  Future<void> _run(Routine r, String why) async {
    r.lastRunMs = DateTime.now().millisecondsSinceEpoch;
    await _save();
    await runner?.call(r.command, why);
  }

  /// Gatilhos de horário (inclui recuperar horários perdidos há até 90 min).
  Future<void> tick() async {
    final now = DateTime.now();
    for (final r in _list) {
      if (!r.active || !r.trigger.startsWith('hora:')) continue;
      final p = r.trigger.substring(5).split(':');
      final at = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      final late = now.difference(at);
      if (!late.isNegative && late.inMinutes <= 90 && r.lastRunMs < at.millisecondsSinceEpoch) {
        await _run(r, 'horário ${r.trigger.substring(5)}');
      }
    }
  }

  /// Gatilhos por evento. [match] diz se o gatilho da rotina corresponde ao evento.
  /// Mínimo de 5 minutos entre execuções da mesma rotina.
  Future<void> fire(bool Function(String trigger) match, String why) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in _list) {
      if (!r.active || r.trigger.startsWith('hora:') || !match(r.trigger)) continue;
      if (now - r.lastRunMs < 5 * 60 * 1000) continue;
      await _run(r, why);
    }
  }
}
