import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'native_bridge.dart';
import 'settings_store.dart';
import 'text_utils.dart';
import 'vault_service.dart';

/// Área de transferência do OpenEXE: até 25 textos e 25 imagens, só neste aparelho.
/// Itens fixados nunca são apagados sozinhos; ao passar do limite sai o mais antigo
/// não fixado. Textos que parecem senha não são guardados.
class ClipboardHistoryService extends ChangeNotifier {
  ClipboardHistoryService(this.settings) {
    _texts = _read(settings.clipJson);
    _imgs = _read(settings.clipImgJson);
  }
  final SettingsStore settings;
  static const maxItems = 25;

  late List<Map<String, dynamic>> _texts; // {t, ms, pin}
  late List<Map<String, dynamic>> _imgs; // {p (caminho), size, ms, pin}

  List<Map<String, dynamic>> _read(String raw) {
    try {
      return [for (final e in jsonDecode(raw) as List) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      return [];
    }
  }

  bool get enabled => settings.clipHistoryOn;
  List<Map<String, dynamic>> get texts => List.unmodifiable(_ordered(_texts));
  List<Map<String, dynamic>> get images => List.unmodifiable(_ordered(_imgs));
  int get count => _texts.length + _imgs.length;

  /// Fixados primeiro, depois o mais novo.
  List<Map<String, dynamic>> _ordered(List<Map<String, dynamic>> l) {
    final r = [...l];
    r.sort((a, b) {
      final pa = a['pin'] == true ? 1 : 0, pb = b['pin'] == true ? 1 : 0;
      if (pa != pb) return pb - pa;
      return ((b['ms'] as num?) ?? 0).compareTo((a['ms'] as num?) ?? 0);
    });
    return r;
  }

  bool _looksLikeSecret(String t) {
    if (t.contains(RegExp(r'\s')) || t.length < 8 || t.length > 64) return false;
    final hasL = t.contains(RegExp(r'[A-Za-z]'));
    final hasD = t.contains(RegExp(r'[0-9]'));
    final hasS = t.contains(RegExp(r'[^A-Za-z0-9]'));
    final mixed = t.contains(RegExp(r'[a-z]')) && t.contains(RegExp(r'[A-Z]'));
    if (t.startsWith('http')) return false;
    return hasL && hasD && (hasS || mixed);
  }

  /// Tira o mais antigo não fixado até caber. Retorna false se tudo está fixado.
  bool _makeRoom(List<Map<String, dynamic>> l, {bool images = false}) {
    while (l.length >= maxItems) {
      final idx = l.lastIndexWhere((e) => e['pin'] != true);
      // l está em ordem de inserção (mais novo no início), então o último não fixado é o mais antigo.
      if (idx < 0) return false;
      final gone = l.removeAt(idx);
      if (images) _deleteFile(gone['p'] as String?);
    }
    return true;
  }

  void _deleteFile(String? p) {
    if (p == null) return;
    try {
      File(p).deleteSync();
    } catch (_) {}
  }

  Future<void> _persist() async {
    await settings.setClipJson(jsonEncode(_texts));
    await settings.setClipImgJson(jsonEncode(_imgs));
    notifyListeners();
  }

  // ---------- Textos ----------
  Future<void> add(String text) async {
    if (!enabled) return;
    final t = text.trim();
    if (t.isEmpty || _looksLikeSecret(t)) return;
    final old = _texts.where((e) => e['t'] == t).toList();
    final pinned = old.any((e) => e['pin'] == true);
    _texts.removeWhere((e) => e['t'] == t);
    if (!_makeRoom(_texts)) return;
    _texts.insert(0, {'t': clip(t, 2000), 'ms': DateTime.now().millisecondsSinceEpoch, 'pin': pinned});
    await _persist();
  }

  Future<void> togglePinText(String t) async {
    for (final e in _texts) {
      if (e['t'] == t) e['pin'] = e['pin'] != true;
    }
    await _persist();
  }

  Future<void> removeText(String t) async {
    _texts.removeWhere((e) => e['t'] == t);
    await _persist();
  }

  // ---------- Imagens ----------
  /// Chame com o app em primeiro plano: o Android só entrega a área de transferência assim.
  Future<bool> checkImage() async {
    if (!enabled) return false;
    final m = await NativeBridge.clipImage();
    if (m == null) return false;
    final path = m['path'] as String;
    final size = (m['size'] as num).toInt();
    if (_imgs.isNotEmpty && _imgs.first['size'] == size) {
      _deleteFile(path); // a mesma imagem de antes
      return false;
    }
    if (!_makeRoom(_imgs, images: true)) {
      _deleteFile(path);
      return false;
    }
    _imgs.insert(0, {'p': path, 'size': size, 'ms': DateTime.now().millisecondsSinceEpoch, 'pin': false});
    await _persist();
    return true;
  }

  Future<void> togglePinImage(String path) async {
    for (final e in _imgs) {
      if (e['p'] == path) e['pin'] = e['pin'] != true;
    }
    await _persist();
  }

  Future<void> removeImage(String path) async {
    _imgs.removeWhere((e) => e['p'] == path);
    _deleteFile(path);
    await _persist();
  }

  Future<bool> copyImage(String path) => NativeBridge.setClipImage(path);

  /// Copia para o Vault (Midia/Imagens). Retorna o caminho novo ou null.
  Future<String?> saveImageToVault(String path) async {
    try {
      final dir = Directory('${VaultService.root}/Midia/Imagens');
      await dir.create(recursive: true);
      final dest = '${dir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).copy(dest);
      return dest;
    } catch (_) {
      return null;
    }
  }

  // ---------- Geral ----------
  Future<void> clearUnpinned() async {
    _texts.removeWhere((e) => e['pin'] != true);
    for (final e in _imgs.where((e) => e['pin'] != true)) {
      _deleteFile(e['p'] as String?);
    }
    _imgs.removeWhere((e) => e['pin'] != true);
    await _persist();
  }

  // ---------- Compatibilidade com o console ----------
  List<String> latest({int n = 10}) => _texts.take(n).map((e) => e['t'] as String).toList();

  List<String> search(String term, {int n = 10}) {
    final q = norm(term);
    return _texts
        .map((e) => e['t'] as String)
        .where((t) => norm(t).contains(q))
        .take(n)
        .toList();
  }

  Future<void> clear() => clearUnpinned();
}
