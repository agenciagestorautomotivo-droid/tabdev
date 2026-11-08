import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import 'settings_store.dart';

/// Dados compartilhados entre o Dock (Q4) e o painel de Apps instalados (Q5).
/// O dock guarda no máximo 5 pastas. App que não está em pasta aparece no Q5 como
/// "sem pasta" (ponto amarelo) até você movê-lo.
class DockModel extends ChangeNotifier {
  DockModel(this.settings);
  final SettingsStore settings;

  static const maxFolders = 5;
  static const defaultNames = ['Mídia', 'Google', 'Social', 'Trabalho', 'Utilitários'];

  bool loading = true;
  List<AppInfo> all = [];
  List<Map<String, dynamic>> folders = [];

  // ---------- Carga ----------
  Future<void> refresh() async {
    try {
      final apps = await InstalledApps.getInstalledApps(false, true);
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final installed = apps.map((a) => a.packageName).toSet();
      var f = _parse(settings.dockV3Json);
      var changed = false;
      if (f == null) {
        f = _migrate(apps);
        changed = true;
      } else if (apps.isNotEmpty) {
        final before = jsonEncode(f);
        f = [
          for (final it in f)
            {...it, 'i': [for (final p in (it['i'] as List)) if (installed.contains(p)) p]},
        ];
        changed = jsonEncode(f) != before;
      }
      all = apps;
      folders = f;
      loading = false;
      if (changed) await _save();
    } catch (_) {
      loading = false;
    }
    notifyListeners();
  }

  List<Map<String, dynamic>>? _parse(String? raw) {
    if (raw == null) return null;
    try {
      return [for (final e in jsonDecode(raw) as List) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      return null;
    }
  }

  /// Primeira vez: aproveita as pastas do dock antigo (v2) e joga os apps soltos em
  /// "Utilitários". Sem dock antigo, separa por palavras-chave.
  List<Map<String, dynamic>> _migrate(List<AppInfo> apps) {
    final installed = apps.map((a) => a.packageName).toSet();
    final byName = <String, List<String>>{for (final n in defaultNames) n: <String>[]};
    final old = _parse(settings.dockJson);
    if (old != null) {
      final extras = <String>[];
      for (final it in old) {
        if (it['t'] == 'folder') {
          final n = '${it['n']}';
          final key = byName.keys.firstWhere((k) => k.toLowerCase() == n.toLowerCase(),
              orElse: () => '');
          final pk = [for (final p in (it['i'] as List)) if (installed.contains(p)) p as String];
          if (key.isNotEmpty) {
            byName[key]!.addAll(pk);
          } else {
            extras.addAll(pk);
          }
        } else if (installed.contains(it['p'])) {
          extras.add(it['p'] as String);
        }
      }
      byName['Utilitários']!.addAll(extras);
    } else {
      _classify(apps, byName);
    }
    return [for (final n in defaultNames) {'t': 'folder', 'n': n, 'i': byName[n]!.toSet().toList()}];
  }

  static const _rules = {
    'Mídia': ['galeria', 'gallery', 'fotos', 'photos', 'video', 'vídeo', 'musica', 'música',
      'music', 'camera', 'câmera', 'spotify', 'youtube', 'player'],
    'Social': ['whatsapp', 'instagram', 'facebook', 'telegram', 'tiktok', 'messenger', 'x ',
      'twitter', 'discord', 'linkedin', 'threads', 'snapchat'],
    'Trabalho': ['docs', 'sheets', 'slides', 'office', 'word', 'excel', 'powerpoint', 'teams',
      'slack', 'zoom', 'notion', 'obsidian', 'drive', 'outlook', 'meet'],
  };

  void _classify(List<AppInfo> apps, Map<String, List<String>> out) {
    for (final a in apps) {
      final n = a.name.toLowerCase();
      final p = a.packageName;
      String? dest;
      for (final e in _rules.entries) {
        if (e.value.any(n.contains)) {
          dest = e.key;
          break;
        }
      }
      if (dest == null && (p.startsWith('com.google.android.apps.') || p == 'com.google.android.gm')) {
        dest = 'Google';
      }
      if (dest != null) out[dest]!.add(p);
    }
  }

  Future<void> _save() => settings.setDockV3Json(jsonEncode(folders));

  // ---------- Consultas ----------
  AppInfo? byPkg(String p) {
    for (final a in all) {
      if (a.packageName == p) return a;
    }
    return null;
  }

  int folderIndexOf(String pkg) {
    for (var i = 0; i < folders.length; i++) {
      if ((folders[i]['i'] as List).contains(pkg)) return i;
    }
    return -1;
  }

  String? folderNameOf(String pkg) {
    final i = folderIndexOf(pkg);
    return i < 0 ? null : '${folders[i]['n']}';
  }

  List<AppInfo> get unfiled => [for (final a in all) if (folderIndexOf(a.packageName) < 0) a];

  // ---------- Edição ----------
  Future<void> moveToFolder(Iterable<String> pkgs, int folder) async {
    if (folder < 0 || folder >= folders.length) return;
    for (final p in pkgs) {
      for (final f in folders) {
        (f['i'] as List).remove(p);
      }
      (folders[folder]['i'] as List).add(p);
    }
    notifyListeners();
    await _save();
  }

  Future<void> removeFromFolder(String pkg) async {
    for (final f in folders) {
      (f['i'] as List).remove(pkg);
    }
    notifyListeners();
    await _save();
  }

  Future<bool> addFolder(String name) async {
    if (folders.length >= maxFolders || name.trim().isEmpty) return false;
    folders.add({'t': 'folder', 'n': name.trim(), 'i': <String>[]});
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> renameFolder(int i, String name) async {
    if (i < 0 || i >= folders.length || name.trim().isEmpty) return;
    folders[i]['n'] = name.trim();
    notifyListeners();
    await _save();
  }

  /// Remove a pasta; os apps dela voltam a ficar "sem pasta".
  Future<void> removeFolder(int i) async {
    if (i < 0 || i >= folders.length) return;
    folders.removeAt(i);
    notifyListeners();
    await _save();
  }

  Future<void> reorderFolder(int from, int to) async {
    if (from == to || from < 0 || to < 0 || from >= folders.length || to >= folders.length) return;
    final x = folders.removeAt(from);
    folders.insert(to, x);
    notifyListeners();
    await _save();
  }
}
