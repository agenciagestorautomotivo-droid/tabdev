import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vault_service.dart';

class TaskItem {
  TaskItem(this.text, this.done);
  final String text;
  bool done;
}

/// Tarefas de hoje: caixas de seleção em Notas/tarefas.md do Vault ("- [ ] algo").
/// O arquivo é Markdown puro, então o Obsidian ou o Claude também podem editá-lo.
class TasksService {
  final ValueNotifier<List<TaskItem>> items = ValueNotifier([]);

  File get _f => File('${VaultService.root}/Notas/tarefas.md');

  static final _re = RegExp(r'^\s*[-*]\s*\[( |x|X)\]\s*(.+)$');

  Future<void> load() async {
    try {
      if (!await _f.exists()) {
        items.value = [];
        return;
      }
      final out = <TaskItem>[];
      for (final l in await _f.readAsLines()) {
        final m = _re.firstMatch(l);
        if (m != null) out.add(TaskItem(m.group(2)!.trim(), m.group(1) != ' '));
      }
      items.value = out;
    } catch (_) {
      items.value = [];
    }
  }

  int get done => items.value.where((e) => e.done).length;
  int get total => items.value.length;
  double get progress => total == 0 ? 0 : done / total;

  Future<void> _save() async {
    try {
      await _f.parent.create(recursive: true);
      final b = StringBuffer('# Tarefas\n\n');
      for (final t in items.value) {
        b.writeln('- [${t.done ? 'x' : ' '}] ${t.text}');
      }
      await _f.writeAsString(b.toString());
    } catch (_) {}
  }

  Future<void> add(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    items.value = [...items.value, TaskItem(t, false)];
    await _save();
  }

  Future<void> toggle(int i) async {
    if (i < 0 || i >= items.value.length) return;
    items.value[i].done = !items.value[i].done;
    items.value = [...items.value];
    await _save();
  }

  Future<void> remove(int i) async {
    if (i < 0 || i >= items.value.length) return;
    final l = [...items.value]..removeAt(i);
    items.value = l;
    await _save();
  }
}
