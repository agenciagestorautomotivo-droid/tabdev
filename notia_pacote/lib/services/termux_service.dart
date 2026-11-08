import 'dart:async';

import 'native_bridge.dart';

class TermuxResult {
  TermuxResult({this.stdout = '', this.stderr = '', this.exit = -1, this.error});
  final String stdout;
  final String stderr;
  final int exit;
  final String? error;
  bool get ok => error == null && exit == 0;

  /// Saída resumida (o fim, que é onde ficam os erros).
  String tail([int n = 1500]) {
    final t = [stdout.trim(), stderr.trim()].where((e) => e.isNotEmpty).join('\n');
    return t.length > n ? '…${t.substring(t.length - n)}' : t;
  }
}

class TermuxState {
  const TermuxState(this.installed, this.perm);
  final bool installed;
  final bool perm;
  bool get ready => installed && perm;
}

/// Terminal Linux (Termux) do tablet. Roda comandos reais e devolve a saída.
class TermuxService {
  static Future<TermuxState> state() async {
    final m = await NativeBridge.termuxState();
    return TermuxState(m['installed'] == true, m['perm'] == true);
  }

  static Future<void> requestPermission() => NativeBridge.termuxPerm();
  static Future<bool> open() => NativeBridge.termuxOpen();

  /// Prepara o ambiente uma vez (colar no Termux): libera apps externos e instala o básico.
  static const bootstrap =
      'mkdir -p ~/.termux ~/projetos && grep -q allow-external-apps ~/.termux/termux.properties 2>/dev/null || '
      'echo "allow-external-apps=true" >> ~/.termux/termux.properties; '
      'termux-reload-settings 2>/dev/null; '
      'pkg update -y && pkg install -y git python nodejs openssh curl wget zip unzip jq nano';

  int _n = 0;

  /// [dir] é relativo à home do Termux (padrão: projetos).
  Future<TermuxResult> run(String cmd, {String dir = 'projetos', Duration timeout = const Duration(minutes: 8)}) async {
    final id = '${DateTime.now().millisecondsSinceEpoch}-${_n++}';
    final full = 'mkdir -p ~/$dir && cd ~/$dir && { $cmd\n}';
    final done = NativeBridge.events
        .firstWhere((e) => e['type'] == 'termux' && e['id'] == id)
        .timeout(timeout, onTimeout: () => <String, dynamic>{'timeout': true});
    final st = await NativeBridge.termuxRun(id, full);
    if (st != 'ok') {
      return TermuxResult(
          error: switch (st) {
        'sem_termux' => 'Termux não está instalado.',
        'sem_permissao' => 'Falta a permissão do Termux (PAINEL > Dev).',
        _ => 'Não consegui falar com o Termux ($st). Rode o preparo em PAINEL > Dev.',
      });
    }
    final e = await done;
    if (e['timeout'] == true) return TermuxResult(error: 'Tempo esgotado (${timeout.inMinutes} min).');
    final msg = '${e['errmsg'] ?? ''}'.trim();
    return TermuxResult(
      stdout: '${e['stdout'] ?? ''}',
      stderr: '${e['stderr'] ?? ''}',
      exit: (e['exit'] as num?)?.toInt() ?? -1,
      error: msg.isEmpty ? null : msg,
    );
  }
}
