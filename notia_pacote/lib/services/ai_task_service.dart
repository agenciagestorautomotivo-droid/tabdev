import 'package:flutter/foundation.dart';

class AiTask {
  AiTask(this.id, this.title, {this.detail = '', this.progress, this.onStop});
  final String id;
  String title;
  String detail;

  /// 0..1; null = andamento sem medida (barra "correndo").
  double? progress;
  VoidCallback? onStop;
  final DateTime started = DateTime.now();
}

/// Tudo o que a IA está fazendo agora, para a barra de tarefas do OpenEXE.
class AiTaskService extends ChangeNotifier {
  final Map<String, AiTask> _t = {};
  String lastDone = '';
  bool lastFailed = false;
  DateTime? lastDoneAt;

  /// Tarefas ativas. Quando o agente de apps está rodando, a tarefa genérica do console some.
  List<AiTask> get active {
    final l = _t.values.toList();
    if (_t.containsKey('agent')) l.removeWhere((e) => e.id == 'console');
    l.sort((a, b) => a.started.compareTo(b.started));
    return l;
  }

  void upsert(String id, String title, {String? detail, double? progress, VoidCallback? onStop}) {
    final t = _t[id];
    if (t == null) {
      _t[id] = AiTask(id, title, detail: detail ?? '', progress: progress, onStop: onStop);
    } else {
      t.title = title;
      if (detail != null) t.detail = detail;
      t.progress = progress;
      if (onStop != null) t.onStop = onStop;
    }
    notifyListeners();
  }

  void finish(String id, {String? result, bool failed = false}) {
    final t = _t.remove(id);
    if (t == null) return;
    if (id != 'console' || result != null) {
      lastDone = result ?? '${t.title} concluído';
      lastFailed = failed;
      lastDoneAt = DateTime.now();
    }
    notifyListeners();
  }
}
