import 'dart:convert';

import 'package:http/http.dart' as http;

import 'settings_store.dart';

/// Repositórios do GitHub mostrados na aba REPOSITÓRIOS do Hub.
/// O repositório padrão (estrela) é o mesmo `gh_repo` usado pelo console (gh:).
class RepoStore {
  RepoStore(this.settings) {
    try {
      _repos = [for (final e in jsonDecode(settings.reposJson) as List) e.toString()];
    } catch (_) {
      _repos = [];
    }
    final d = settings.ghRepo;
    if (d.isNotEmpty && !_repos.contains(d)) _repos.insert(0, d);
  }
  final SettingsStore settings;
  late List<String> _repos;
  static final _re = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

  List<String> get all => List.unmodifiable(_repos);
  String get defaultRepo => settings.ghRepo;

  /// Aceita "dono/repo" ou uma URL do github.com. Retorna null se inválido.
  static String? parse(String input) {
    var s = input.trim();
    s = s.replaceFirst(RegExp(r'^https?://(www\.)?github\.com/'), '');
    s = s.replaceFirst(RegExp(r'\.git$'), '').replaceAll(RegExp(r'/+$'), '');
    final parts = s.split('/');
    if (parts.length >= 2) s = '${parts[0]}/${parts[1]}';
    return _re.hasMatch(s) ? s : null;
  }

  Future<bool> add(String input) async {
    final r = parse(input);
    if (r == null) return false;
    if (!_repos.contains(r)) _repos.add(r);
    if (settings.ghRepo.isEmpty) await settings.setGhRepo(r);
    await _save();
    return true;
  }

  Future<void> remove(String repo) async {
    _repos.remove(repo);
    if (settings.ghRepo == repo) await settings.setGhRepo(_repos.isEmpty ? '' : _repos.first);
    await _save();
  }

  Future<void> setDefault(String repo) => settings.setGhRepo(repo);

  Future<void> _save() => settings.setReposJson(jsonEncode(_repos));

  String url(String repo) => 'https://github.com/$repo';

  /// Lista os repositórios da conta (precisa do token do GitHub em CONFIG). Null se falhar.
  Future<List<String>?> fetchMine() async {
    if (settings.ghToken.isEmpty) return null;
    try {
      final r = await http.get(
        Uri.parse('https://api.github.com/user/repos?per_page=50&sort=pushed'),
        headers: {
          'Authorization': 'Bearer ${settings.ghToken}',
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      return [for (final e in jsonDecode(r.body) as List) (e as Map)['full_name'] as String];
    } catch (_) {
      return null;
    }
  }
}
