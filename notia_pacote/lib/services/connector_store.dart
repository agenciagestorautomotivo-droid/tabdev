import 'dart:convert';

import 'package:http/http.dart' as http;

import 'settings_store.dart';

/// Conector próprio: um endereço HTTP (webhook, n8n, Zapier, Make, API sua) que recebe
/// `{"text": "...", "source": "openexe"}` por POST e devolve texto ou JSON.
class Connector {
  Connector(this.name, this.url, {this.auth = ''});
  String name;
  String url;
  String auth; // valor completo do cabeçalho Authorization (opcional)
  Map<String, dynamic> toJson() => {'n': name, 'u': url, 'a': auth};
  static Connector fromJson(Map<String, dynamic> j) =>
      Connector('${j['n']}', '${j['u']}', auth: '${j['a'] ?? ''}');
}

class ConnectorStore {
  ConnectorStore(this.settings) {
    try {
      _list = [
        for (final e in jsonDecode(settings.connectorsJson) as List)
          Connector.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (_) {
      _list = [];
    }
  }
  final SettingsStore settings;
  late List<Connector> _list;

  List<Connector> get all => List.unmodifiable(_list);

  Connector? byName(String n) {
    for (final c in _list) {
      if (c.name.toLowerCase() == n.trim().toLowerCase()) return c;
    }
    return null;
  }

  Future<void> _save() => settings.setConnectorsJson(jsonEncode(_list.map((e) => e.toJson()).toList()));

  Future<void> upsert(Connector c, {String? oldName}) async {
    final key = (oldName ?? c.name).toLowerCase();
    final i = _list.indexWhere((e) => e.name.toLowerCase() == key);
    if (i >= 0) {
      _list[i] = c;
    } else {
      _list.add(c);
    }
    await _save();
  }

  Future<void> remove(String name) async {
    _list.removeWhere((e) => e.name.toLowerCase() == name.toLowerCase());
    await _save();
  }

  /// Envia o texto e devolve a resposta (ou o erro, em texto).
  Future<String> call(Connector c, String text) async {
    try {
      final uri = Uri.parse(c.url);
      if (!uri.hasScheme || !(uri.scheme == 'https' || uri.scheme == 'http')) {
        return 'Endereço inválido (use http:// ou https://).';
      }
      final r = await http
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                if (c.auth.isNotEmpty) 'Authorization': c.auth,
              },
              body: jsonEncode({'text': text, 'source': 'openexe'}))
          .timeout(const Duration(seconds: 20));
      final body = utf8.decode(r.bodyBytes).trim();
      final short = body.length > 600 ? '${body.substring(0, 600)}…' : body;
      return r.statusCode >= 200 && r.statusCode < 300
          ? (short.isEmpty ? 'OK (${r.statusCode})' : short)
          : 'Erro ${r.statusCode}: $short';
    } catch (e) {
      return 'Falhou: ${e.toString().replaceFirst('Exception: ', '')}';
    }
  }
}
