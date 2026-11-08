import 'dart:convert';

import 'package:http/http.dart' as http;

import 'settings_store.dart';

/// GitHub REST API v3, sem interface pesada. O token (PAT com escopo repo) fica
/// só neste aparelho. Toda ação que escreve no GitHub deve ser confirmada antes
/// de chamar estes métodos (o console faz isso).
class GitHubSyncService {
  GitHubSyncService(this.settings);
  final SettingsStore settings;

  String lastError = '';
  static final _repoRe = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${settings.ghToken}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      };

  bool _ready(String repo) {
    if (settings.ghToken.isEmpty) {
      lastError = 'Token do GitHub ausente (CONFIG).';
      return false;
    }
    if (!_repoRe.hasMatch(repo)) {
      lastError = 'Repositório inválido. Use dono/repo.';
      return false;
    }
    return true;
  }

  /// Cria ou atualiza um arquivo no repositório.
  Future<bool> commitNota(String repo, String path, String content, String message) async {
    if (!_ready(repo)) return false;
    final enc = path.split('/').map(Uri.encodeComponent).join('/');
    final url = Uri.parse('https://api.github.com/repos/$repo/contents/$enc');
    try {
      String? sha;
      final get = await http.get(url, headers: _headers).timeout(const Duration(seconds: 15));
      if (get.statusCode == 200) {
        sha = (jsonDecode(get.body) as Map)['sha'] as String?;
      } else if (get.statusCode != 404) {
        lastError = 'GitHub respondeu ${get.statusCode} ao consultar o arquivo.';
        return false;
      }
      final put = await http
          .put(
            url,
            headers: _headers,
            body: jsonEncode({
              'message': message,
              'content': base64Encode(utf8.encode(content)),
              if (sha != null) 'sha': sha,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (put.statusCode == 200 || put.statusCode == 201) return true;
      lastError = 'GitHub respondeu ${put.statusCode} ao gravar.';
      return false;
    } catch (e) {
      lastError = 'Falha de rede.';
      return false;
    }
  }

  /// Dispara um repository_dispatch (GitHub Actions).
  Future<bool> triggerWorkflow(
      String repo, String eventType, Map<String, dynamic> clientPayload) async {
    if (!_ready(repo)) return false;
    try {
      final res = await http
          .post(
            Uri.parse('https://api.github.com/repos/$repo/dispatches'),
            headers: _headers,
            body: jsonEncode({'event_type': eventType, 'client_payload': clientPayload}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 204) return true;
      lastError = 'GitHub respondeu ${res.statusCode} ao disparar.';
      return false;
    } catch (e) {
      lastError = 'Falha de rede.';
      return false;
    }
  }
}
