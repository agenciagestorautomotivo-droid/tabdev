import 'package:flutter/material.dart';

import 'theme.dart';

/// Tela de bloqueio do OpenEXE: aparece por cima do launcher. Ela é uma camada a mais; o
/// bloqueio do sistema Android continua existindo e nenhum launcher consegue substituí-lo.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.now,
    required this.nextEvent,
    required this.notifCount,
    required this.onUnlock,
  });
  final DateTime now;
  final String nextEvent;
  final int notifCount;
  final Future<bool> Function() onUnlock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;
  String _msg = '';

  static const _dias = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
  static const _meses = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro',
    'outubro', 'novembro', 'dezembro'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  Future<void> _try() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    final ok = await widget.onUnlock();
    if (mounted && !ok) {
      setState(() {
        _busy = false;
        _msg = 'Não foi possível destravar. Tente de novo.';
      });
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final n = widget.now;
    return GestureDetector(
      onTap: _try,
      child: Container(
        color: N.bg,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('OpenEXE', style: N.t(c: N.cyan, s: 14, w: FontWeight.w700, ls: 2)),
          const SizedBox(height: 18),
          Text('${_two(n.hour)}:${_two(n.minute)}',
              style: N.t(s: 96, w: FontWeight.w700, ls: 2)),
          const SizedBox(height: 4),
          Text('${_dias[n.weekday - 1]}, ${n.day} de ${_meses[n.month - 1]}',
              style: N.t(c: N.dim, s: 18)),
          const SizedBox(height: 28),
          if (widget.nextEvent.isNotEmpty)
            Text('Próximo compromisso: ${widget.nextEvent}', style: N.t(c: N.amber, s: 14)),
          if (widget.notifCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${widget.notifCount} notificações', style: N.t(c: N.dim, s: 13)),
            ),
          const SizedBox(height: 36),
          NBtn(_busy ? 'AGUARDANDO…' : 'TOQUE PARA DESTRAVAR', accent: true, onTap: _try),
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_msg, style: N.t(c: N.red, s: 12)),
            ),
        ]),
      ),
    );
  }
}
