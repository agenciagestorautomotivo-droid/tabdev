import 'package:local_auth/local_auth.dart';

/// Trava por biometria (digital/rosto) ou pelo PIN/padrão do aparelho.
class LockService {
  final _auth = LocalAuthentication();

  Future<bool> supported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Se o aparelho não tem trava de tela, devolve true (não há como proteger).
  Future<bool> authenticate(String reason) async {
    if (!await supported()) return true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
