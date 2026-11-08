import 'dart:async';

import 'package:flutter/foundation.dart';

import 'native_bridge.dart';

/// Leitura do aparelho para o cartão RAM · MEMÓRIA · CPU · TEMP do rodapé.
class SysStats {
  const SysStats({
    this.ramPct = 0,
    this.ramUsedGb = 0,
    this.ramTotalGb = 0,
    this.storPct = 0,
    this.storUsedGb = 0,
    this.storTotalGb = 0,
    this.cpuPct = -1,
    this.cpuSource = 'none',
    this.temp = -1,
    this.tempSource = 'none',
    this.ok = false,
  });
  final int ramPct;
  final double ramUsedGb, ramTotalGb;
  final int storPct;
  final double storUsedGb, storTotalGb;
  final int cpuPct;
  final String cpuSource;
  final double temp;
  final String tempSource;
  final bool ok;

  /// Aviso honesto quando o Android não deixa ler o valor real.
  String get cpuNote => switch (cpuSource) {
        'stat' => 'uso geral',
        'freq' => 'estimado pela frequência',
        'app' => 'só deste app',
        _ => 'indisponível',
      };
  String get tempNote => switch (tempSource) {
        'thermal' => 'sensor térmico',
        'battery' => 'temperatura da bateria',
        _ => 'indisponível',
      };
}

class SystemMonitorService {
  final ValueNotifier<SysStats> stats = ValueNotifier(const SysStats());
  Timer? _t;

  static const _gb = 1024 * 1024 * 1024;

  void start({Duration every = const Duration(seconds: 3)}) {
    _t?.cancel();
    _tick();
    _t = Timer.periodic(every, (_) => _tick());
  }

  void stop() {
    _t?.cancel();
    _t = null;
  }

  void dispose() {
    stop();
    stats.dispose();
  }

  Future<void> _tick() async {
    final m = await NativeBridge.sysStats();
    if (m == null) return;
    double n(String k) => ((m[k] as num?) ?? 0).toDouble();
    final rt = n('ramTotal'), ra = n('ramAvail');
    final st = n('storTotal'), sf = n('storFree');
    final ru = rt - ra, su = st - sf;
    stats.value = SysStats(
      ramPct: rt > 0 ? (ru / rt * 100).round() : 0,
      ramUsedGb: ru / _gb,
      ramTotalGb: rt / _gb,
      storPct: st > 0 ? (su / st * 100).round() : 0,
      storUsedGb: su / _gb,
      storTotalGb: st / _gb,
      cpuPct: (m['cpuPct'] as num?)?.toInt() ?? -1,
      cpuSource: (m['cpuSource'] as String?) ?? 'none',
      temp: n('temp') <= 0 ? -1 : n('temp'),
      tempSource: (m['tempSource'] as String?) ?? 'none',
      ok: true,
    );
  }
}
