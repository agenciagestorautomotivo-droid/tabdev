import 'dart:async';

import 'package:flutter/foundation.dart';

import 'native_bridge.dart';

/// Teclado do VAIO TL10: o teclado magnético conta como teclado físico.
/// Automático: físico conectado = "TECLADO FÍSICO"; desconectado = "TECLADO VIRTUAL".
/// Tocar no botão força o outro modo até o estado físico mudar de novo.
class KeyboardMode extends ChangeNotifier {
  bool _physical = false;
  bool? _forceVirtual; // null = automático
  StreamSubscription<Map<String, dynamic>>? _sub;

  bool get physical => _physical;

  /// true = o campo do console usa o teclado virtual na tela.
  bool get useVirtual => _forceVirtual ?? !_physical;

  String get label => useVirtual ? 'TECLADO VIRTUAL' : 'TECLADO FÍSICO';

  Future<void> init() async {
    _physical = await NativeBridge.physicalKeyboard();
    _sub = NativeBridge.events.where((e) => e['type'] == 'keyboard').listen((e) {
      final p = e['physical'] == true;
      if (p != _physical) {
        _physical = p;
        _forceVirtual = null; // mudou o hardware: volta ao automático
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// Alterna manualmente. Sem teclado físico conectado, só há o virtual.
  void toggle() {
    if (!_physical) return;
    _forceVirtual = useVirtual ? false : true;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
