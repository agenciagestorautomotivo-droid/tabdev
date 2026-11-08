import 'package:permission_handler/permission_handler.dart';

import 'native_bridge.dart';
import 'notia_brain.dart';

/// Agenda do próprio aparelho (a que o app Calendário do Android mostra, incluindo
/// o que já sincronizou com Google, Outlook etc.). Grava um resumo em `agenda_local`.
class LocalCalendarService {
  LocalCalendarService(this.brain);
  final NotiaBrain brain;
  String lastError = '';

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<List<String>?> upcoming({int hours = 24}) async {
    lastError = '';
    final st = await Permission.calendar.request();
    if (!st.isGranted) {
      lastError = 'Sem permissão de calendário. Libere em Configurações > Apps > Notia.';
      return null;
    }
    final from = DateTime.now();
    final ev = await NativeBridge.calendarEvents(from, from.add(Duration(hours: hours)));
    if (ev == null) {
      lastError = 'Não consegui ler o calendário do aparelho.';
      return null;
    }
    final lines = <String>[];
    for (final e in ev) {
      final b = DateTime.fromMillisecondsSinceEpoch((e['begin'] as num).toInt());
      final when = e['allDay'] == true ? 'dia todo' : '${_two(b.hour)}:${_two(b.minute)}';
      final where = (e['where'] as String).isEmpty ? '' : ' (${e['where']})';
      lines.add('$when ${e['title']}$where');
    }
    await brain.setKv('agenda_local', lines.isEmpty ? 'sem compromissos' : lines.join('; '),
        categoria: 'agenda');
    return lines;
  }

  /// Próximo compromisso nas próximas 24 h: {title, begin(DateTime), where} ou null.
  Future<Map<String, dynamic>?> next() async {
    final st = await Permission.calendar.status;
    if (!st.isGranted) return null;
    final now = DateTime.now();
    final ev = await NativeBridge.calendarEvents(now, now.add(const Duration(hours: 24)));
    if (ev == null) return null;
    for (final e in ev) {
      final b = DateTime.fromMillisecondsSinceEpoch((e['begin'] as num).toInt());
      if (e['allDay'] == true || b.isBefore(now)) continue;
      return {'title': e['title'], 'begin': b, 'where': e['where']};
    }
    return null;
  }

  /// "em 3 h", "em 25 min", "agora".
  static String until(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.inMinutes < 1) return 'agora';
    if (d.inMinutes < 60) return 'em ${d.inMinutes} min';
    final h = d.inHours, m = d.inMinutes % 60;
    return m == 0 || h >= 3 ? 'em $h h' : 'em $h h ${m}min';
  }
}
