import 'native_bridge.dart';
import 'text_utils.dart';

class NotifItem {
  NotifItem(this.key, this.pkg, this.app, this.title, this.text, this.time);
  final String key;
  final String pkg;
  final String app;
  final String title;
  final String text;
  final DateTime time;

  String get hhmm =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Notificações dos outros apps (via NotificationListenerService). Ficam só na memória:
/// as últimas 100. A lista e a limpeza são locais (0 tokens); o resumo usa a IA com
/// uma versão enxuta (app, título e 80 caracteres do texto).
class NotificationService {
  final List<NotifItem> items = [];
  final Set<String> _seen = {};

  /// Chamado para cada notificação nova (depois da carga inicial).
  void Function(NotifItem item)? onNew;

  Future<void> init() async {
    for (final m in await NativeBridge.recentNotifications(limit: 100)) {
      ingest(m, silent: true);
    }
  }

  void ingest(Map<String, dynamic> m, {bool silent = false}) {
    final id = '${m['key']}|${m['time']}';
    if (!_seen.add(id)) return;
    final it = NotifItem(
      '${m['key']}',
      '${m['pkg']}',
      '${m['app']}',
      '${m['title']}',
      '${m['text']}',
      DateTime.fromMillisecondsSinceEpoch((m['time'] as num).toInt()),
    );
    items.add(it);
    while (items.length > 100) {
      items.removeAt(0);
    }
    if (!silent) onNew?.call(it);
  }

  List<NotifItem> latest({int n = 15, String? app}) {
    var l = items.reversed.toList();
    if (app != null && app.isNotEmpty) {
      final a = norm(app);
      l = l.where((e) => norm(e.app).contains(a) || norm(e.pkg).contains(a)).toList();
    }
    return l.take(n).toList();
  }

  String listText({int n = 15, String? app}) {
    final l = latest(n: n, app: app);
    if (l.isEmpty) return 'Nenhuma notificação guardada${app == null ? '' : ' de "$app"'}.';
    return l
        .map((e) => '${e.hhmm} ${e.app}: ${e.title}${e.text.isEmpty ? '' : ' — ${clip(e.text, 90)}'}')
        .join('\n');
  }

  /// Versão compacta para a IA resumir.
  String forAi({int n = 25}) => latest(n: n)
      .map((e) => '${e.app}|${clip(e.title, 40)}|${clip(e.text, 80)}')
      .join('\n');

  Future<void> clear() async {
    items.clear();
    _seen.clear();
    await NativeBridge.clearNotifications();
  }
}
