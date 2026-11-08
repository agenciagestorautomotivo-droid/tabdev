import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'notia_brain.dart';
import 'settings_store.dart';
import 'vault_service.dart';

/// Login Google com escopos mínimos: drive.file (só arquivos criados pelo Notia)
/// e calendar.readonly (só leitura da agenda).
class GoogleAuthService {
  final _gs = GoogleSignIn(scopes: const [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/calendar.readonly',
  ]);
  GoogleSignInAccount? _account;
  String lastError = '';

  String? get email => _account?.email;
  bool get signedIn => _account != null;

  Future<bool> signInSilently() async {
    try {
      _account = await _gs.signInSilently();
    } catch (_) {
      _account = null;
    }
    return _account != null;
  }

  Future<bool> signIn() async {
    try {
      _account = await _gs.signIn();
      if (_account == null) lastError = 'Login cancelado.';
    } catch (e) {
      lastError =
          'Não consegui entrar no Google. Confira o cliente OAuth (pacote com.notia.os.notia e SHA-1).';
      _account = null;
    }
    return _account != null;
  }

  Future<void> signOut() async {
    await _gs.signOut();
    _account = null;
  }

  Future<Map<String, String>?> headers() async {
    if (_account == null && !await signInSilently()) return null;
    return _account!.authHeaders;
  }
}

/// Backup incremental de tudo no Google Drive: Vault inteiro (notas, memória, diário,
/// mídias) mais um snapshot do SQLite. Só sobe o que mudou desde o último backup.
class DriveBackupService {
  DriveBackupService(this.auth, this.brain, this.settings);
  final GoogleAuthService auth;
  final NotiaBrain brain;
  final SettingsStore settings;

  /// OFF, ENVIANDO, SYNCED ou ERRO.
  final status = ValueNotifier<String>('OFF');
  String lastError = '';
  bool _busy = false;

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _up = 'https://www.googleapis.com/upload/drive/v3';
  static const _rootName = 'Notia Backup';
  static const _maxBytes = 50 * 1024 * 1024;
  static const _folderMime = 'application/vnd.google-apps.folder';

  final _folderIds = <String, String>{};

  Future<String> _folder(String name, String? parent, Map<String, String> h) async {
    final cacheKey = '${parent ?? 'root'}/$name';
    final hit = _folderIds[cacheKey];
    if (hit != null) return hit;
    final q =
        "mimeType='$_folderMime' and name='${name.replaceAll("'", "\\'")}' and trashed=false and '${parent ?? 'root'}' in parents";
    final r = await http.get(
        Uri.parse('$_api/files?q=${Uri.encodeQueryComponent(q)}&fields=files(id)&spaces=drive'),
        headers: h);
    if (r.statusCode != 200) throw Exception('Drive ${r.statusCode}');
    final files = (jsonDecode(r.body)['files'] as List);
    String id;
    if (files.isNotEmpty) {
      id = files.first['id'] as String;
    } else {
      final c = await http.post(Uri.parse('$_api/files?fields=id'),
          headers: {...h, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'mimeType': _folderMime,
            if (parent != null) 'parents': [parent],
          }));
      if (c.statusCode != 200) throw Exception('Drive ${c.statusCode}');
      id = jsonDecode(c.body)['id'] as String;
    }
    _folderIds[cacheKey] = id;
    return id;
  }

  Future<String> _folderPath(String relDir, Map<String, String> h) async {
    var parent = await _folder(_rootName, null, h);
    if (relDir.isEmpty) return parent;
    for (final part in relDir.split('/')) {
      parent = await _folder(part, parent, h);
    }
    return parent;
  }

  Future<String> _upload(String name, Uint8List bytes, String mime, String parentId,
      String? existingId, Map<String, String> h) async {
    final meta = jsonEncode({'name': name, if (existingId == null) 'parents': [parentId]});
    if (bytes.length <= 5 * 1024 * 1024) {
      const b = 'notia_boundary_7f3a';
      final body = BytesBuilder()
        ..add(utf8.encode('--$b\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'))
        ..add(utf8.encode('--$b\r\nContent-Type: $mime\r\n\r\n'))
        ..add(bytes)
        ..add(utf8.encode('\r\n--$b--'));
      final url = existingId == null
          ? '$_up/files?uploadType=multipart&fields=id'
          : '$_up/files/$existingId?uploadType=multipart&fields=id';
      final req = http.Request(existingId == null ? 'POST' : 'PATCH', Uri.parse(url))
        ..headers.addAll({...h, 'Content-Type': 'multipart/related; boundary=$b'})
        ..bodyBytes = body.toBytes();
      final r = await http.Response.fromStream(await req.send());
      if (r.statusCode != 200) throw Exception('Drive ${r.statusCode}');
      return jsonDecode(r.body)['id'] as String;
    }
    // Arquivos grandes: envio resumível.
    final initUrl = existingId == null
        ? '$_up/files?uploadType=resumable&fields=id'
        : '$_up/files/$existingId?uploadType=resumable&fields=id';
    final init = http.Request(existingId == null ? 'POST' : 'PATCH', Uri.parse(initUrl))
      ..headers.addAll({
        ...h,
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': mime,
      })
      ..body = meta;
    final ir = await http.Response.fromStream(await init.send());
    final loc = ir.headers['location'];
    if (ir.statusCode != 200 || loc == null) throw Exception('Drive ${ir.statusCode}');
    final put = await http.put(Uri.parse(loc), headers: {'Content-Type': mime}, body: bytes);
    if (put.statusCode != 200 && put.statusCode != 201) throw Exception('Drive ${put.statusCode}');
    return jsonDecode(put.body)['id'] as String;
  }

  String _mime(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.md')) return 'text/markdown';
    if (p.endsWith('.json')) return 'application/json';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.wav')) return 'audio/wav';
    if (p.endsWith('.flac')) return 'audio/flac';
    if (p.endsWith('.ogg')) return 'audio/ogg';
    return 'application/octet-stream';
  }

  /// Envia o que mudou. Retorna um resumo curto; em falha, retorna null e preenche lastError.
  Future<String?> backup() async {
    if (_busy) return 'Já há um backup em andamento.';
    _busy = true;
    try {
      status.value = 'ENVIANDO';
      final h = await auth.headers();
      if (h == null) {
        lastError = 'Entre com sua conta Google em CONFIG.';
        status.value = 'OFF';
        return null;
      }
      final manifest = Map<String, dynamic>.from(jsonDecode(settings.driveManifest) as Map);
      var sent = 0, same = 0, skipped = 0;

      Future<void> push(String rel, Uint8List bytes, int mtime) async {
        final prev = manifest[rel] as Map?;
        if (prev != null && prev['m'] == mtime && prev['s'] == bytes.length) {
          same++;
          return;
        }
        final slash = rel.lastIndexOf('/');
        final dir = slash < 0 ? '' : rel.substring(0, slash);
        final name = slash < 0 ? rel : rel.substring(slash + 1);
        final parent = await _folderPath(dir, h);
        final id = await _upload(name, bytes, _mime(rel), parent, prev?['id'] as String?, h);
        manifest[rel] = {'m': mtime, 's': bytes.length, 'id': id};
        sent++;
      }

      // 1) Snapshot do SQLite (sempre atual).
      final snap = <String, Object?>{};
      for (final t in NotiaBrain.syncTables) {
        snap[t] = await brain.exportTable(t);
      }
      final snapBytes = Uint8List.fromList(utf8.encode(jsonEncode(snap)));
      await push('_snapshot/notia_snapshot.json', snapBytes, DateTime.now().millisecondsSinceEpoch);

      // 2) Vault inteiro.
      final root = Directory(VaultService.root);
      if (await root.exists()) {
        await for (final e in root.list(recursive: true)) {
          if (e is! File) continue;
          final rel = e.path.substring(VaultService.root.length + 1);
          if (rel.split('/').any((p) => p.startsWith('.'))) continue;
          final stat = await e.stat();
          if (stat.size > _maxBytes) {
            skipped++;
            continue;
          }
          await push(rel, await e.readAsBytes(), stat.modified.millisecondsSinceEpoch);
        }
      }

      await settings.setDriveManifest(jsonEncode(manifest));
      await settings.setLastBackupMs(DateTime.now().millisecondsSinceEpoch);
      status.value = 'SYNCED';
      await brain.logEvent('drive_backup', 'enviados $sent');
      return 'Backup no Drive: $sent enviado(s), $same sem mudança${skipped > 0 ? ', $skipped grande(s) ignorado(s)' : ''}.';
    } catch (e) {
      lastError = 'Falha no backup do Drive: ${e.toString().replaceFirst('Exception: ', '')}';
      status.value = 'ERRO';
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<List<Map<String, dynamic>>> _children(String id, Map<String, String> h) async {
    final out = <Map<String, dynamic>>[];
    String? token;
    do {
      final q = "'$id' in parents and trashed=false";
      final r = await http.get(
          Uri.parse(
              '$_api/files?q=${Uri.encodeQueryComponent(q)}&fields=nextPageToken,files(id,name,mimeType)&pageSize=200${token != null ? '&pageToken=$token' : ''}'),
          headers: h);
      if (r.statusCode != 200) throw Exception('Drive ${r.statusCode}');
      final j = jsonDecode(r.body) as Map;
      out.addAll((j['files'] as List).cast<Map<String, dynamic>>());
      token = j['nextPageToken'] as String?;
    } while (token != null);
    return out;
  }

  /// Baixa o backup: grava os arquivos no Vault e restaura o snapshot do SQLite.
  /// Confirme com o usuário antes de chamar.
  Future<String?> restore() async {
    if (_busy) return 'Já há uma operação em andamento.';
    _busy = true;
    try {
      status.value = 'ENVIANDO';
      final h = await auth.headers();
      if (h == null) {
        lastError = 'Entre com sua conta Google em CONFIG.';
        status.value = 'OFF';
        return null;
      }
      final rootId = await _folder(_rootName, null, h);
      var files = 0;
      Future<void> walk(String id, String rel) async {
        for (final c in await _children(id, h)) {
          final name = c['name'] as String;
          final path = rel.isEmpty ? name : '$rel/$name';
          if (name.contains('..') || name.contains('/')) continue;
          if (c['mimeType'] == _folderMime) {
            await walk(c['id'] as String, path);
            continue;
          }
          final r = await http.get(Uri.parse('$_api/files/${c['id']}?alt=media'), headers: h);
          if (r.statusCode != 200) continue;
          if (path == '_snapshot/notia_snapshot.json') {
            final snap = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
            for (final t in NotiaBrain.syncTables) {
              final rows = snap[t];
              if (rows is List) await brain.replaceTable(t, rows.cast<Map>());
            }
          } else {
            final f = File('${VaultService.root}/$path');
            await f.parent.create(recursive: true);
            await f.writeAsBytes(r.bodyBytes);
          }
          files++;
        }
      }

      await walk(rootId, '');
      await brain.syncFromVault();
      status.value = 'SYNCED';
      return 'Restaurado do Drive: $files arquivo(s).';
    } catch (e) {
      lastError = 'Falha ao restaurar: ${e.toString().replaceFirst('Exception: ', '')}';
      status.value = 'ERRO';
      return null;
    } finally {
      _busy = false;
    }
  }

  /// Backup automático: no máximo uma vez a cada 6 horas.
  Future<void> maybeAutoBackup() async {
    if (!settings.driveAuto || !auth.signedIn) return;
    final age = DateTime.now().millisecondsSinceEpoch - settings.lastBackupMs;
    if (age > 6 * 3600 * 1000) await backup();
  }
}

/// Google Agenda (somente leitura): compromissos das próximas 24 h viram a memória
/// `agenda_hoje`, uma linha curta que só entra nos prompts quando o assunto é agenda.
class CalendarService {
  CalendarService(this.auth, this.brain);
  final GoogleAuthService auth;
  final NotiaBrain brain;
  String lastError = '';

  Future<List<String>?> sync() async {
    final h = await auth.headers();
    if (h == null) {
      lastError = 'Entre com sua conta Google em CONFIG.';
      return null;
    }
    try {
      final now = DateTime.now().toUtc();
      final url = Uri.parse('https://www.googleapis.com/calendar/v3/calendars/primary/events'
          '?timeMin=${Uri.encodeQueryComponent(now.toIso8601String())}'
          '&timeMax=${Uri.encodeQueryComponent(now.add(const Duration(hours: 24)).toIso8601String())}'
          '&singleEvents=true&orderBy=startTime&maxResults=15');
      final r = await http.get(url, headers: h);
      if (r.statusCode != 200) {
        lastError = 'Agenda respondeu ${r.statusCode}.';
        return null;
      }
      final items = (jsonDecode(r.body)['items'] as List?) ?? [];
      final lines = <String>[];
      for (final e in items) {
        final title = (e['summary'] as String?) ?? '(sem título)';
        final s = e['start'] as Map?;
        final dt = s?['dateTime'] as String?;
        var when = 'dia todo';
        if (dt != null) {
          final d = DateTime.parse(dt).toLocal();
          when =
              '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        }
        lines.add('$when $title');
      }
      await brain.setKv('agenda_hoje', lines.isEmpty ? 'sem compromissos' : lines.join('; '),
          categoria: 'agenda');
      return lines;
    } catch (_) {
      lastError = 'Falha de rede ao ler a agenda.';
      return null;
    }
  }
}
