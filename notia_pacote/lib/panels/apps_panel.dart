import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../services/dock_model.dart';
import '../services/native_bridge.dart';
import '../services/text_utils.dart';
import '../theme.dart';

/// Q5: todos os apps instalados. Busca, filtros (TODOS, SEM PASTA, RECENTES) e organização
/// em pastas do dock. Ponto amarelo = app que ainda não está em nenhuma pasta.
/// O Android não informa quantas atualizações a Play Store tem pendentes, então
/// ATUALIZAÇÕES e ATUALIZAR TUDO abrem a Play Store (Gerenciar apps).
class AppsPanel extends StatefulWidget {
  const AppsPanel({super.key, required this.model, required this.onStore});
  final DockModel model;
  final VoidCallback onStore;

  @override
  State<AppsPanel> createState() => _AppsPanelState();
}

class _AppsPanelState extends State<AppsPanel> {
  DockModel get _m => widget.model;
  final _q = TextEditingController();
  String _filter = 'todos';
  bool _editing = false;
  final _sel = <String>{};

  @override
  void initState() {
    super.initState();
    _m.addListener(_on);
  }

  void _on() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _m.removeListener(_on);
    _q.dispose();
    super.dispose();
  }

  /// Data de instalação (se a versão do plugin informar); 0 quando não houver.
  int _ts(AppInfo a) {
    try {
      return ((a as dynamic).installedTimestamp as num).toInt();
    } catch (_) {
      return 0;
    }
  }

  List<AppInfo> _shown() {
    var l = [..._m.all];
    final q = norm(_q.text);
    if (q.isNotEmpty) l = l.where((a) => norm(a.name).contains(q)).toList();
    switch (_filter) {
      case 'sem':
        l = l.where((a) => _m.folderIndexOf(a.packageName) < 0).toList();
      case 'recentes':
        l.sort((a, b) => _ts(b).compareTo(_ts(a)));
        l = l.take(20).toList();
    }
    return l;
  }

  Widget _chip(String label, bool active, VoidCallback onTap, {int? badge}) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? N.cyan : N.bg,
            border: Border.all(color: active ? N.cyan : N.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(badge == null ? label : '$label $badge',
              style: N.t(c: active ? N.bg : N.dim, s: 11, w: FontWeight.w700)),
        ),
      );

  Widget _icon(AppInfo a, double size) {
    final bytes = a.icon;
    if (bytes == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: N.line2, borderRadius: BorderRadius.circular(size / 4)),
        child: Text(a.name.isEmpty ? '?' : a.name[0].toUpperCase(), style: N.t(w: FontWeight.w700)),
      );
    }
    return Image.memory(bytes, width: size, height: size, gaplessPlayback: true);
  }

  Widget _tile(AppInfo a) {
    final unfiled = _m.folderIndexOf(a.packageName) < 0;
    final selected = _sel.contains(a.packageName);
    return InkWell(
      onTap: () {
        if (_editing) {
          setState(() => selected ? _sel.remove(a.packageName) : _sel.add(a.packageName));
        } else {
          InstalledApps.startApp(a.packageName);
        }
      },
      onLongPress: () => _menu(a),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: selected ? N.cyan : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _icon(a, 36),
              const SizedBox(height: 2),
              Text(a.name,
                  style: N.t(c: N.dim, s: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ]),
          ),
          if (unfiled)
            Positioned(
              right: 6,
              top: 2,
              child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: N.amber, shape: BoxShape.circle)),
            ),
        ]),
      ),
    );
  }

  Future<int?> _pickFolder() => showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: N.bg,
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
          title: Text('Mover para qual pasta?', style: N.t(c: N.cyan, w: FontWeight.w700)),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < _m.folders.length; i++)
                ListTile(
                  dense: true,
                  title: Text('${_m.folders[i]['n']}', style: N.t()),
                  trailing: Text('${(_m.folders[i]['i'] as List).length}', style: N.t(c: N.dim)),
                  onTap: () => Navigator.pop(ctx, i),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text('CANCELAR', style: N.t(c: N.dim))),
          ],
        ),
      );

  Future<void> _moveSelected() async {
    if (_sel.isEmpty) {
      _toast('Toque nos apps para marcar e depois em MOVER PARA PASTA.');
      return;
    }
    final i = await _pickFolder();
    if (i == null) return;
    final n = _sel.length;
    await _m.moveToFolder(_sel.toList(), i);
    setState(_sel.clear);
    _toast('$n app(s) movido(s) para ${_m.folders[i]['n']}.');
  }

  Future<void> _menu(AppInfo a) async {
    final act = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: N.bg,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
        title: Text(a.name, style: N.t(c: N.cyan, w: FontWeight.w700)),
        children: [
          for (final e in const [
            ('abrir', 'Abrir'),
            ('mover', 'Mover para pasta'),
            ('tirar', 'Tirar da pasta'),
            ('info', 'Informações do app'),
            ('del', 'Desinstalar'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.$1),
              child: Text(e.$2, style: N.t(c: e.$1 == 'del' ? N.red : N.text)),
            ),
        ],
      ),
    );
    switch (act) {
      case 'abrir':
        InstalledApps.startApp(a.packageName);
      case 'mover':
        final i = await _pickFolder();
        if (i != null) await _m.moveToFolder([a.packageName], i);
      case 'tirar':
        await _m.removeFromFolder(a.packageName);
      case 'info':
        await NativeBridge.appInfo(a.packageName);
      case 'del':
        // O próprio Android pede a confirmação final.
        await NativeBridge.uninstall(a.packageName);
        Future.delayed(const Duration(seconds: 4), _m.refresh);
    }
  }

  void _toast(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Widget _btn(String t, VoidCallback onTap, {bool accent = false}) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              border: Border.all(color: accent ? N.cyan : N.border),
              borderRadius: BorderRadius.circular(4)),
          child: Text(t, style: N.t(c: accent ? N.cyan : N.dim, s: 11, w: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final list = _shown();
    final noFolder = _m.unfiled.length;
    return Column(children: [
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line2))),
        child: Row(children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _chip('TODOS', _filter == 'todos', () => setState(() => _filter = 'todos'),
                    badge: _m.all.length),
                _chip('SEM PASTA', _filter == 'sem', () => setState(() => _filter = 'sem'),
                    badge: noFolder),
                _chip('RECENTES', _filter == 'recentes', () => setState(() => _filter = 'recentes')),
                _chip('ATUALIZAÇÕES', false, () {
                  _toast('O Android não informa as atualizações pendentes. Abrindo a Play Store.');
                  widget.onStore();
                }),
              ],
            ),
          ),
          _chip(_editing ? 'CONCLUIR' : 'EDITAR', _editing, () {
            setState(() {
              _editing = !_editing;
              _sel.clear();
            });
          }),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: SizedBox(
          height: 34,
          child: TextField(
            controller: _q,
            style: N.t(s: 12),
            cursorColor: N.cyan,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: N.field,
              hintText: 'Buscar app instalado',
              hintStyle: N.t(c: N.dim, s: 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: N.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: N.cyan)),
            ),
          ),
        ),
      ),
      Expanded(
        child: _m.loading
            ? Center(child: Text('Carregando apps…', style: N.t(c: N.dim)))
            : list.isEmpty
                ? Center(child: Text('Nenhum app aqui.', style: N.t(c: N.dim)))
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 76, mainAxisExtent: 62),
                    itemCount: list.length,
                    itemBuilder: (c, i) => _tile(list[i]),
                  ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: Row(children: [
          _btn('PLAY STORE', widget.onStore, accent: true),
          _btn('ATUALIZAR TUDO', () {
            _toast('Na Play Store: toque na sua foto > Gerenciar apps > Atualizar tudo.');
            widget.onStore();
          }),
          _btn(_editing && _sel.isNotEmpty ? 'MOVER ${_sel.length} PARA PASTA' : 'MOVER PARA PASTA',
              () {
            if (!_editing) {
              setState(() => _editing = true);
              _toast('Toque nos apps para marcar, depois em MOVER PARA PASTA.');
            } else {
              _moveSelected();
            }
          }),
          const Spacer(),
          Text('${list.length} apps · ● sem pasta', style: N.t(c: N.dim, s: 10)),
        ]),
      ),
    ]);
  }
}
