import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notia_brain.dart';
import 'settings_store.dart';

/// Backup relacional no Supabase (tier gratuito) e notificações em tempo real.
/// Autentica com e-mail e senha de um usuário seu; as políticas RLS de
/// supabase_schema.sql só deixam esse usuário ler e gravar os próprios dados.
class SupabaseSyncService {
  SupabaseSyncService(this.settings, this.brain);
  final SettingsStore settings;
  final NotiaBrain brain;

  /// OFF, CONECTANDO, SYNCING, SYNCED, CONECTADO ou ERRO.
  final status = ValueNotifier<String>('OFF');
  String lastError = '';
  void Function(String mensagem)? onNotification;

  SupabaseClient? _client;
  RealtimeChannel? _channel;

  bool get configured =>
      settings.sbUrl.isNotEmpty &&
      settings.sbAnonKey.isNotEmpty &&
      settings.sbEmail.isNotEmpty &&
      settings.sbPassword.isNotEmpty;

  Future<bool> connect() async {
    if (!configured) {
      status.value = 'OFF';
      return false;
    }
    try {
      status.value = 'CONECTANDO';
      _client ??= SupabaseClient(settings.sbUrl, settings.sbAnonKey);
      if (_client!.auth.currentSession == null) {
        await _client!.auth
            .signInWithPassword(email: settings.sbEmail, password: settings.sbPassword);
      }
      _listen();
      status.value = 'CONECTADO';
      return true;
    } catch (e) {
      lastError = 'Não consegui entrar no Supabase. Confira URL, chave, e-mail e senha.';
      status.value = 'ERRO';
      return false;
    }
  }

  /// Chame depois de mudar as credenciais em CONFIG.
  Future<bool> reconnect() async {
    await disconnect();
    return connect();
  }

  Future<void> disconnect() async {
    try {
      await _channel?.unsubscribe();
      await _client?.dispose();
    } catch (_) {}
    _channel = null;
    _client = null;
  }

  void _listen() {
    _channel?.unsubscribe();
    _channel = _client!
        .channel('notia-notificacoes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificacoes',
          callback: (payload) {
            final m = payload.newRecord['mensagem'];
            if (m is String && m.isNotEmpty) onNotification?.call(m);
          },
        )
        .subscribe();
  }

  Future<bool> backup() async {
    if (!await connect()) return false;
    try {
      status.value = 'SYNCING';
      final uid = _client!.auth.currentUser!.id;
      for (final t in NotiaBrain.syncTables) {
        final rows = await brain.exportTable(t);
        await _client!.from('notia_snapshots').upsert({
          'owner': uid,
          'tabela': t,
          'dados': rows,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'owner,tabela');
      }
      status.value = 'SYNCED';
      return true;
    } catch (e) {
      lastError = 'Falha ao enviar o backup. Rode o supabase_schema.sql no seu projeto.';
      status.value = 'ERRO';
      return false;
    }
  }

  /// Substitui as tabelas locais pelo último snapshot. Confirme antes de chamar.
  Future<bool> restore() async {
    if (!await connect()) return false;
    try {
      status.value = 'SYNCING';
      final data = await _client!.from('notia_snapshots').select('tabela,dados');
      if (data.isEmpty) {
        lastError = 'Não há backup na nuvem.';
        status.value = 'CONECTADO';
        return false;
      }
      for (final row in data) {
        final t = row['tabela'] as String;
        if (!NotiaBrain.syncTables.contains(t)) continue;
        await brain.replaceTable(t, (row['dados'] as List).cast<Map>());
      }
      status.value = 'SYNCED';
      return true;
    } catch (e) {
      lastError = 'Falha ao restaurar o backup.';
      status.value = 'ERRO';
      return false;
    }
  }
}
