import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

/// Bateria: avisa quando o carregador é ligado (para rotinas) e diz se é uma boa hora
/// para tarefas pesadas, como o backup automático no Drive.
class PowerService {
  final _b = Battery();
  final level = ValueNotifier<int>(100);
  BatteryState state = BatteryState.unknown;
  StreamSubscription? _sub;
  Timer? _timer;

  void Function()? onPlugged;

  bool get charging =>
      state == BatteryState.charging ||
      state == BatteryState.full ||
      state == BatteryState.connectedNotCharging;

  bool get low => level.value < 20 && !charging;

  /// Backup só no Wi-Fi e com carregador ou pelo menos 30% de bateria.
  bool backupOk(bool wifi) => wifi && (charging || level.value >= 30);

  Future<void> start() async {
    try {
      level.value = await _b.batteryLevel;
      state = await _b.batteryState;
    } catch (_) {}
    _sub = _b.onBatteryStateChanged.listen((s) {
      final was = charging;
      state = s;
      if (!was && charging) onPlugged?.call();
    });
    _timer = Timer.periodic(const Duration(minutes: 2), (_) async {
      try {
        level.value = await _b.batteryLevel;
      } catch (_) {}
    });
  }

  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
  }
}
