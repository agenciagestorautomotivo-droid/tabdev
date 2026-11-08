import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/clipboard_history_service.dart';
import 'theme.dart';

/// Popup da área de transferência: textos à esquerda, imagens à direita (25 de cada).
Future<void> showClipboardPopup(BuildContext context, ClipboardHistoryService clip) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ClipPopup(clip: clip),
  );
}

class _ClipPopup extends StatefulWidget {
  const _ClipPopup({required this.clip});
  final ClipboardHistoryService clip;

  @override
  State<_ClipPopup> createState() => _ClipPopupState();
}

class _ClipPopupState extends State<_ClipPopup> {
  final _q = TextEditingController();
  String? _selImg;

  ClipboardHistoryService get _c => widget.clip;

  @override
  void initState() {
    super.initState();
    _c.addListener(_on);
    _c.checkImage(); // pega a imagem que estiver copiada agora
  }

  void _on() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_on);
    _q.dispose();
    super.dispose();
  }

  void _toast(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Widget _mini(String t, VoidCallback onTap, {Color? color}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Text(t, style: N.t(c: color ?? N.dim, s: 11, w: FontWeight.w700)),
        ),
      );

  Widget _head(String title, int n, {Widget? trailing}) => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line2))),
        child: Row(children: [
          Text(title, style: N.t(c: N.cyan, w: FontWeight.w700)),
          const SizedBox(width: 8),
          Text('$n / ${ClipboardHistoryService.maxItems}', style: N.t(c: N.dim, s: 11)),
          const Spacer(),
          if (trailing != null) trailing,
        ]),
      );

  Widget _textsSide() {
    final q = _q.text.toLowerCase();
    final list = [
      for (final e in _c.texts)
        if (q.isEmpty || (e['t'] as String).toLowerCase().contains(q)) e
    ];
    return Column(children: [
      _head('TEXTOS', _c.texts.length),
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
              hintText: 'Buscar nos textos',
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
        child: list.isEmpty
            ? Center(child: Text('Nenhum texto copiado ainda.', style: N.t(c: N.dim)))
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final t = list[i]['t'] as String;
                  final pin = list[i]['pin'] == true;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: pin ? N.amber : N.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                          child: Text(t, style: N.t(s: 12), maxLines: 3, overflow: TextOverflow.ellipsis)),
                      Column(children: [
                        _mini('COPIAR', () async {
                          await Clipboard.setData(ClipboardData(text: t));
                          _toast('Copiado.');
                        }, color: N.cyan),
                        _mini(pin ? 'DESFIXAR' : 'FIXAR', () => _c.togglePinText(t),
                            color: pin ? N.amber : N.dim),
                        _mini('APAGAR', () => _c.removeText(t), color: N.red),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _imagesSide() {
    final list = _c.images;
    final sel = list.where((e) => e['p'] == _selImg).toList();
    final selected = sel.isEmpty ? null : sel.first;
    return Column(children: [
      _head('IMAGENS', list.length),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                    'Nenhuma imagem. Copie uma imagem em qualquer app e volte aqui: o Android só deixa o OpenEXE ler a área de transferência com ele aberto.',
                    textAlign: TextAlign.center,
                    style: N.t(c: N.dim, s: 12)),
              ))
            : GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 110, mainAxisSpacing: 8, crossAxisSpacing: 8),
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final p = list[i]['p'] as String;
                  final pin = list[i]['pin'] == true;
                  return InkWell(
                    onTap: () => setState(() => _selImg = p),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: p == _selImg ? N.cyan : (pin ? N.amber : N.border),
                            width: p == _selImg ? 2 : 1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Stack(fit: StackFit.expand, children: [
                          Image.file(File(p),
                              fit: BoxFit.cover,
                              cacheWidth: 220,
                              errorBuilder: (c, e, s) => Container(color: N.line2)),
                          if (pin)
                            Positioned(
                                right: 4,
                                top: 2,
                                child: Text('★', style: N.t(c: N.amber, s: 14))),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
      if (selected != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: N.line2))),
          child: Row(children: [
            _mini('COPIAR', () async {
              final ok = await _c.copyImage(selected['p'] as String);
              _toast(ok ? 'Imagem copiada.' : 'Não consegui copiar a imagem.');
            }, color: N.cyan),
            _mini(selected['pin'] == true ? 'DESFIXAR' : 'FIXAR',
                () => _c.togglePinImage(selected['p'] as String),
                color: N.amber),
            _mini('SALVAR NO VAULT', () async {
              final r = await _c.saveImageToVault(selected['p'] as String);
              _toast(r == null
                  ? 'Não consegui salvar (permissão "Todos os arquivos"?).'
                  : 'Salvo em Midia/Imagens do Vault.');
            }, color: N.green),
            _mini('APAGAR', () {
              _c.removeImage(selected['p'] as String);
              setState(() => _selImg = null);
            }, color: N.red),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: N.bg,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: N.border), borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 1000,
        height: 600,
        child: Column(children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: N.line))),
            child: Row(children: [
              Text('ÁREA DE TRANSFERÊNCIA', style: N.t(c: N.cyan, w: FontWeight.w700, ls: 1)),
              const Spacer(),
              _mini('LIMPAR NÃO FIXADOS', () async {
                await _c.clearUnpinned();
                _toast('Itens não fixados apagados.');
              }, color: N.red),
              _mini('FECHAR', () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: Row(children: [
              Expanded(child: _textsSide()),
              Container(width: 1, color: N.line),
              Expanded(child: _imagesSide()),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: N.line2))),
            child: Row(children: [
              Expanded(
                child: Text(
                    'Fixados nunca são apagados sozinhos. Textos que parecem senha não são guardados. Ao passar de 25, sai o mais antigo não fixado. Tudo fica só neste aparelho.',
                    style: N.t(c: N.dim, s: 10)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
