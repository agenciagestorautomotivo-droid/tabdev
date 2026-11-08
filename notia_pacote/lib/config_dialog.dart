import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/ai_router.dart';
import 'services/device_kit.dart';
import 'services/native_bridge.dart';
import 'services/google_services.dart';
import 'services/notia_brain.dart';
import 'services/settings_store.dart';
import 'services/supabase_sync_service.dart';
import 'theme.dart';

/// Tela de configurações: IAs, Google, GitHub, Supabase e geral.
Future<void> showConfigDialog(
  BuildContext context, {
  required SettingsStore settings,
  required NotiaBrain brain,
  required AiRouter router,
  required GoogleAuthService google,
  required DriveBackupService drive,
  required SupabaseSyncService sb,
  required DeviceKit kit,
  required VoidCallback onChanged,
}) async {
  final s = settings;
  final name = TextEditingController(text: await brain.getKv('usuario_nome') ?? '');
  final groq = TextEditingController(text: s.groqKey);
  final gem = TextEditingController(text: s.geminiKey);
  final gemModel = TextEditingController(text: s.geminiModel);
  final orr = TextEditingController(text: s.openrouterKey);
  final hf = TextEditingController(text: s.hfToken);
  final ghTok = TextEditingController(text: s.ghToken);
  final ghRepo = TextEditingController(text: s.ghRepo);
  final sbUrl = TextEditingController(text: s.sbUrl);
  final sbAnon = TextEditingController(text: s.sbAnonKey);
  final sbMail = TextEditingController(text: s.sbEmail);
  final sbPass = TextEditingController(text: s.sbPassword);
  final alarm = TextEditingController(text: s.alarmLabel);
  final cName = TextEditingController();
  final cUrl = TextEditingController();
  final cModel = TextEditingController();
  final cKey = TextEditingController();
  var customs = s.customProviders;
  var specialist = s.specialist;
  var speak = s.speakReplies;
  var driveAuto = s.driveAuto;
  var clipOn = s.clipHistoryOn;
  var lockCfg = s.lockConfig;
  var lockVault = s.lockVault;
  var a11yOn = await NativeBridge.a11yEnabled();
  var notifOn = await NativeBridge.notifEnabled();
  var permMsg = '';
  var googleMsg = google.signedIn ? 'Conectado: ${google.email}' : 'Não conectado';
  if (!context.mounted) return;

  InputDecoration dec(String h) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: N.field,
        labelText: h,
        labelStyle: N.t(c: N.dim, s: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: N.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: N.cyan)),
      );

  Widget field(TextEditingController c, String label, {bool secret = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: c, obscureText: secret, style: N.t(), decoration: dec(label)),
      );

  Widget section(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(t, style: N.t(c: N.cyan, w: FontWeight.w700)),
      );

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final ids = {'auto', 'groq', 'gemini', 'openrouter', ...customs.map((c) => (c['name'] ?? '').toLowerCase())};
      if (!ids.contains(specialist)) specialist = 'auto';
      return Dialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 620,
          height: 640,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(children: [
                  Expanded(
                      child: Text('Configurações',
                          style: N.t(c: N.cyan, w: FontWeight.w700, s: 15))),
                  NBtn('Cancelar', onTap: () => Navigator.pop(ctx)),
                  const SizedBox(width: 8),
                  NBtn('Salvar', accent: true, onTap: () async {
                    await s.setGroqKey(groq.text);
                    await s.setGeminiKey(gem.text);
                    await s.setGeminiModel(gemModel.text.trim().isEmpty ? 'gemini-2.5-flash' : gemModel.text);
                    await s.setOpenrouterKey(orr.text);
                    await s.setHfToken(hf.text);
                    await s.setSpecialist(specialist);
                    await s.setCustomProviders(customs);
                    await s.setGhToken(ghTok.text);
                    await s.setGhRepo(ghRepo.text);
                    await s.setSupabase(sbUrl.text, sbAnon.text, sbMail.text, sbPass.text);
                    await s.setAlarmLabel(alarm.text.trim().isEmpty ? '--:--' : alarm.text.trim());
                    await s.setSpeakReplies(speak);
                    await s.setDriveAuto(driveAuto);
                    await s.setClipHistoryOn(clipOn);
                    await s.setLockConfig(lockCfg);
                    await s.setLockVault(lockVault);
                    if (name.text.trim().isNotEmpty) {
                      await brain.remember('usuario_nome', name.text.trim());
                    }
                    sb.reconnect();
                    onChanged();
                    if (ctx.mounted) Navigator.pop(ctx);
                  }),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    section('Você'),
                    field(name, 'Seu nome (memória)'),
                    section('IAs de texto (qualquer uma serve; Groq e Gemini têm camada grátis)'),
                    field(groq, 'Chave Groq', secret: true),
                    field(gem, 'Chave Gemini (aistudio.google.com/apikey)', secret: true),
                    field(gemModel, 'Modelo do Gemini'),
                    field(orr, 'Chave OpenRouter', secret: true),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButtonFormField<String>(
                        value: specialist,
                        dropdownColor: N.field,
                        style: N.t(),
                        decoration: dec('Especialista para pedidos complexos'),
                        items: [
                          for (final i in ids) DropdownMenuItem(value: i, child: Text(i)),
                        ],
                        onChanged: (v) => setD(() => specialist = v ?? 'auto'),
                      ),
                    ),
                    section('IA própria (qualquer serviço compatível com a API OpenAI)'),
                    for (var i = 0; i < customs.length; i++)
                      Row(children: [
                        Expanded(
                            child: Text('${customs[i]['name']} · ${customs[i]['model']} · ${customs[i]['baseUrl']}',
                                style: N.t(c: N.dim, s: 12), overflow: TextOverflow.ellipsis)),
                        TextButton(
                            onPressed: () => setD(() => customs.removeAt(i)),
                            child: Text('remover', style: N.t(c: N.red, s: 12))),
                      ]),
                    field(cName, 'Nome (ex.: deepseek)'),
                    field(cUrl, 'URL base (ex.: https://api.deepseek.com/v1)'),
                    field(cModel, 'Modelo'),
                    field(cKey, 'Chave', secret: true),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NBtn('Adicionar IA', onTap: () {
                        if (cName.text.trim().isEmpty ||
                            !cUrl.text.trim().startsWith('http') ||
                            cModel.text.trim().isEmpty) {
                          return;
                        }
                        setD(() {
                          customs = [
                            ...customs,
                            {
                              'name': cName.text.trim(),
                              'baseUrl': cUrl.text.trim(),
                              'model': cModel.text.trim(),
                              'key': cKey.text.trim(),
                            }
                          ];
                          cName.clear();
                          cUrl.clear();
                          cModel.clear();
                          cKey.clear();
                        });
                      }),
                    ),
                    section('Música por IA'),
                    field(hf, 'Token Hugging Face (grátis, para o MusicGen)', secret: true),
                    section('Google (Drive e Agenda)'),
                    Text(googleMsg, style: N.t(c: N.dim, s: 12)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      NBtn(google.signedIn ? 'Trocar conta' : 'Entrar com Google',
                          accent: true, onTap: () async {
                        final ok = await google.signIn();
                        setD(() => googleMsg =
                            ok ? 'Conectado: ${google.email}' : google.lastError);
                      }),
                      if (google.signedIn)
                        NBtn('Sair', onTap: () async {
                          await google.signOut();
                          setD(() => googleMsg = 'Não conectado');
                        }),
                      NBtn('Backup agora', onTap: () async {
                        setD(() => googleMsg = 'Enviando ao Drive…');
                        final r = await drive.backup();
                        setD(() => googleMsg = r ?? drive.lastError);
                      }),
                    ]),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Backup automático (a cada 6 horas)', style: N.t()),
                      value: driveAuto,
                      activeColor: N.cyan,
                      onChanged: (v) => setD(() => driveAuto = v),
                    ),
                    section('GitHub'),
                    field(ghTok, 'Token (PAT, escopo repo)', secret: true),
                    field(ghRepo, 'Repositório padrão (dono/repo)'),
                    section('Supabase (opcional)'),
                    field(sbUrl, 'URL do projeto'),
                    field(sbAnon, 'Chave anon', secret: true),
                    field(sbMail, 'E-mail'),
                    field(sbPass, 'Senha', secret: true),
                    section('Recursos do aparelho'),
                    Text(
                        'Controle de apps: ${a11yOn ? 'ATIVO' : 'desligado'}   ·   '
                        'Notificações: ${notifOn ? 'ATIVAS' : 'desligadas'}',
                        style: N.t(c: a11yOn && notifOn ? N.green : N.amber, s: 12)),
                    const SizedBox(height: 4),
                    Text(
                        'No Android 13, apps instalados por APK vêm com esses dois bloqueados. '
                        'Primeiro toque em "Liberar configurações restritas", abra o menu de 3 pontinhos '
                        'e escolha "Permitir configurações restritas". Depois ative os dois serviços.',
                        style: N.t(c: N.dim, s: 11)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      NBtn('Liberar configurações restritas',
                          onTap: () => NativeBridge.openSettings('appdetails')),
                      NBtn('Ativar controle de apps',
                          accent: true, onTap: () => NativeBridge.openSettings('accessibility')),
                      NBtn('Ativar notificações',
                          accent: true, onTap: () => NativeBridge.openSettings('notifications')),
                      NBtn('Atualizar status', onTap: () async {
                        final a = await NativeBridge.a11yEnabled();
                        final n = await NativeBridge.notifEnabled();
                        setD(() {
                          a11yOn = a;
                          notifOn = n;
                        });
                      }),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      NBtn('Permitir contatos', onTap: () async {
                        final r = await Permission.contacts.request();
                        setD(() => permMsg = 'Contatos: ${r.isGranted ? 'liberado' : 'negado'}');
                      }),
                      NBtn('Permitir calendário', onTap: () async {
                        final r = await Permission.calendar.request();
                        setD(() => permMsg = 'Calendário: ${r.isGranted ? 'liberado' : 'negado'}');
                      }),
                      NBtn('Permitir localização', onTap: () async {
                        final r = await Permission.locationWhenInUse.request();
                        setD(() => permMsg = 'Localização: ${r.isGranted ? 'liberada' : 'negada'}');
                      }),
                      NBtn('Ignorar economia de bateria',
                          onTap: () => NativeBridge.openSettings('battery')),
                    ]),
                    if (permMsg.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(permMsg, style: N.t(c: N.dim, s: 12)),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Guardar histórico da área de transferência', style: N.t()),
                      value: clipOn,
                      activeColor: N.cyan,
                      onChanged: (v) => setD(() => clipOn = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Pedir digital/PIN para abrir a CONFIG', style: N.t()),
                      value: lockCfg,
                      activeColor: N.cyan,
                      onChanged: (v) => setD(() => lockCfg = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Travar o Vault (pede digital/PIN após 5 min fora)', style: N.t()),
                      value: lockVault,
                      activeColor: N.cyan,
                      onChanged: (v) => setD(() => lockVault = v),
                    ),
                    Text(
                        'Rotinas: ${kit.routines.all.length} · Lugares: ${kit.places.places.length}. '
                        'Gerencie pelo console (digite "ajuda").',
                        style: N.t(c: N.dim, s: 11)),
                    section('Geral'),
                    field(alarm, 'Alarme exibido no topo (ex.: 06:30)'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Falar as respostas', style: N.t()),
                      value: speak,
                      activeColor: N.cyan,
                      onChanged: (v) => setD(() => speak = v),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NBtn('Liberar acesso a arquivos (Vault)', onTap: () async {
                        await Permission.manageExternalStorage.request();
                      }),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
    }),
  );
}
