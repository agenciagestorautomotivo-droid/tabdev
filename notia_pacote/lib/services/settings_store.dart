import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Preferências locais (pasta privada do app): chaves, dock, hub, layout.
class SettingsStore {
  SettingsStore._(this._p);
  final SharedPreferences _p;

  static Future<SettingsStore> load() async =>
      SettingsStore._(await SharedPreferences.getInstance());

  String _s(String k) => _p.getString(k) ?? '';
  Future<void> _set(String k, String v) => _p.setString(k, v.trim());

  // --- Provedores de IA ---
  String get groqKey => _s('groq_key');
  String get openrouterKey => _s('openrouter_key');
  String get geminiKey => _s('gemini_key');
  String get geminiModel => _p.getString('gemini_model') ?? 'gemini-2.5-flash';
  String get hfToken => _s('hf_token');
  Future<void> setGroqKey(String v) => _set('groq_key', v);
  Future<void> setOpenrouterKey(String v) => _set('openrouter_key', v);
  Future<void> setGeminiKey(String v) => _set('gemini_key', v);
  Future<void> setGeminiModel(String v) => _set('gemini_model', v);
  Future<void> setHfToken(String v) => _set('hf_token', v);

  /// Quem atende pedidos complexos: 'auto', 'gemini', 'openrouter', 'groq' ou o nome de um provedor próprio.
  String get specialist => _p.getString('specialist') ?? 'auto';
  Future<void> setSpecialist(String v) => _set('specialist', v);

  /// Provedores próprios compatíveis com a API OpenAI: [{name, baseUrl, model, key}].
  List<Map<String, String>> get customProviders {
    try {
      final l = jsonDecode(_p.getString('custom_providers') ?? '[]') as List;
      return [for (final e in l) Map<String, String>.from(e as Map)];
    } catch (_) {
      return [];
    }
  }

  Future<void> setCustomProviders(List<Map<String, String>> v) =>
      _p.setString('custom_providers', jsonEncode(v));

  // --- GitHub ---
  String get ghToken => _s('gh_token');
  String get ghRepo => _s('gh_repo');
  Future<void> setGhToken(String v) => _set('gh_token', v);
  Future<void> setGhRepo(String v) => _set('gh_repo', v);

  // --- Supabase ---
  String get sbUrl => _s('sb_url');
  String get sbAnonKey => _s('sb_anon');
  String get sbEmail => _s('sb_email');
  String get sbPassword => _p.getString('sb_pass') ?? '';
  Future<void> setSupabase(String url, String anon, String email, String pass) async {
    await _set('sb_url', url);
    await _set('sb_anon', anon);
    await _set('sb_email', email);
    await _p.setString('sb_pass', pass);
  }

  // --- Google Drive ---
  bool get driveAuto => _p.getBool('drive_auto') ?? true;
  Future<void> setDriveAuto(bool v) => _p.setBool('drive_auto', v);
  int get lastBackupMs => _p.getInt('last_backup_ms') ?? 0;
  Future<void> setLastBackupMs(int v) => _p.setInt('last_backup_ms', v);
  String get driveManifest => _p.getString('drive_manifest') ?? '{}';
  Future<void> setDriveManifest(String v) => _p.setString('drive_manifest', v);

  // --- Voz e alarme ---
  bool get speakReplies => _p.getBool('speak_replies') ?? true;
  Future<void> setSpeakReplies(bool v) => _p.setBool('speak_replies', v);
  String get alarmLabel => _p.getString('alarm_label') ?? '--:--';
  Future<void> setAlarmLabel(String v) => _p.setString('alarm_label', v);

  // --- Apps já vistos (para detectar instalações novas da Play Store) ---
  List<String> get dockKnown => _p.getStringList('dock_known') ?? [];
  Future<void> setDockKnown(List<String> v) => _p.setStringList('dock_known', v);

  // --- Dock e Hub (JSON) ---
  String? get dockJson => _p.getString('dock_v2');
  Future<void> setDockJson(String v) => _p.setString('dock_v2', v);
  String? get hubJson => _p.getString('hub_v1');
  Future<void> setHubJson(String v) => _p.setString('hub_v1', v);

  // --- Recursos do aparelho ---
  String get routinesJson => _p.getString('routines_v1') ?? '[]';
  Future<void> setRoutinesJson(String v) => _p.setString('routines_v1', v);
  String get placesJson => _p.getString('places_v1') ?? '[]';
  Future<void> setPlacesJson(String v) => _p.setString('places_v1', v);
  String get clipJson => _p.getString('clip_hist') ?? '[]';
  Future<void> setClipJson(String v) => _p.setString('clip_hist', v);
  bool get clipHistoryOn => _p.getBool('clip_hist_on') ?? true;
  Future<void> setClipHistoryOn(bool v) => _p.setBool('clip_hist_on', v);
  /// Trechos de nome de app cujas notificações o Notia lê em voz alta.
  List<String> get notifSpeak => _p.getStringList('notif_speak') ?? [];
  Future<void> setNotifSpeak(List<String> v) => _p.setStringList('notif_speak', v);
  bool get lockConfig => _p.getBool('lock_config') ?? false;
  Future<void> setLockConfig(bool v) => _p.setBool('lock_config', v);
  bool get lockVault => _p.getBool('lock_vault') ?? false;
  Future<void> setLockVault(bool v) => _p.setBool('lock_vault', v);

  // --- Atualização automática do OpenEXE (APK nos Releases do GitHub) ---
  bool get autoUpdate => _p.getBool('auto_update') ?? true;
  Future<void> setAutoUpdate(bool v) => _p.setBool('auto_update', v);
  String get updateRepo => _p.getString('update_repo') ?? 'agenciagestorautomotivo-droid/tabdev';
  Future<void> setUpdateRepo(String v) => _p.setString('update_repo', v.trim());
  String get downloadedBuild => _p.getString('update_dl_build') ?? '';
  Future<void> setDownloadedBuild(String v) => _p.setString('update_dl_build', v);

  // --- OpenEXE: dock v3 (até 5 pastas), repositórios, modo foco, imagens da área de transferência ---
  String? get dockV3Json => _p.getString('dock_v3');
  Future<void> setDockV3Json(String v) => _p.setString('dock_v3', v);
  String get reposJson => _p.getString('repos_v1') ?? '[]';
  Future<void> setReposJson(String v) => _p.setString('repos_v1', v);
  bool get focusMode => _p.getBool('focus_mode') ?? false;
  Future<void> setFocusMode(bool v) => _p.setBool('focus_mode', v);
  String get clipImgJson => _p.getString('clip_imgs') ?? '[]';
  Future<void> setClipImgJson(String v) => _p.setString('clip_imgs', v);

  // --- Layout editável (5 módulos: esquerda 2, direita 3) ---
  /// slots5[i] = módulo na posição i. Posições 0-1 = coluna esquerda (cima, baixo);
  /// 2-4 = coluna direita (cima, meio, baixo).
  /// Módulos: 0 console, 1 hub de IAs, 2 cérebro/vault, 3 dock, 4 apps instalados.
  List<int> get slots5 {
    final l = _p.getStringList('slots5');
    const def = [0, 2, 1, 4, 3];
    if (l == null || l.length != 5) return def;
    final v = l.map((e) => int.tryParse(e) ?? -1).toList();
    if (v.toSet().length != 5 || v.any((e) => e < 0 || e > 4)) return def;
    return v;
  }

  Future<void> setSlots5(List<int> v) =>
      _p.setStringList('slots5', v.map((e) => e.toString()).toList());

  double get col5 => (_p.getDouble('col5') ?? 0.46).clamp(0.3, 0.7);
  double get left5 => (_p.getDouble('left5') ?? 0.56).clamp(0.25, 0.75);
  double get rightA5 => (_p.getDouble('right_a5') ?? 0.36).clamp(0.15, 0.6);
  double get rightB5 => (_p.getDouble('right_b5') ?? 0.30).clamp(0.15, 0.6);
  Future<void> setSplits5(double col, double left, double ra, double rb) async {
    await _p.setDouble('col5', col);
    await _p.setDouble('left5', left);
    await _p.setDouble('right_a5', ra);
    await _p.setDouble('right_b5', rb);
  }

  // --- Layout editável ---
  double get colSplit => (_p.getDouble('col_split') ?? 0.5).clamp(0.3, 0.7);
  double get leftRowSplit => (_p.getDouble('left_row_split') ?? 0.5).clamp(0.3, 0.7);
  double get rightRowSplit => (_p.getDouble('right_row_split') ?? 0.5).clamp(0.3, 0.7);
  Future<void> setSplits(double col, double left, double right) async {
    await _p.setDouble('col_split', col);
    await _p.setDouble('left_row_split', left);
    await _p.setDouble('right_row_split', right);
  }

  /// slots[i] = módulo no quadrante i (0 sup.esq, 1 sup.dir, 2 inf.esq, 3 inf.dir).
  /// Módulos: 0 console, 1 hub de IAs, 2 vault e cérebro, 3 dock e navegador.
  List<int> get slots {
    final l = _p.getStringList('slots');
    if (l == null || l.length != 4) return [0, 1, 2, 3];
    final v = l.map((e) => int.tryParse(e) ?? -1).toList();
    if (v.toSet().length != 4 || v.any((e) => e < 0 || e > 3)) return [0, 1, 2, 3];
    return v;
  }

  Future<void> setSlots(List<int> v) =>
      _p.setStringList('slots', v.map((e) => e.toString()).toList());
}
