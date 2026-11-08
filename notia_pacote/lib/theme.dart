import 'package:flutter/material.dart';

/// Paleta e estilos do Notia (OLED black, sem sombras nem blur).
class N {
  static const bg = Color(0xFF0A0A0C);
  static const line = Color(0xFF23232B);
  static const line2 = Color(0xFF1A1A21);
  static const border = Color(0xFF2E2E38);
  static const field = Color(0xFF101014);
  static const cyan = Color(0xFF5EEAD4);
  static const green = Color(0xFF86EFAC);
  static const amber = Color(0xFFFCD34D);
  static const violet = Color(0xFFC4B5FD);
  static const red = Color(0xFFFCA5A5);
  static const text = Color(0xFFE6E6EA);
  static const dim = Color(0xFFA0A0AC);

  static TextStyle t({
    Color c = text,
    double s = 13,
    FontWeight w = FontWeight.w400,
    double ls = 0,
  }) =>
      TextStyle(
        color: c,
        fontSize: s,
        fontWeight: w,
        fontFamily: 'monospace',
        letterSpacing: ls,
        height: 1.45,
      );
}

/// Botão retangular simples da barra inferior e dos painéis.
class NBtn extends StatelessWidget {
  const NBtn(this.label, {super.key, this.onTap, this.accent = false, this.width});
  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final color = accent ? N.cyan : N.text;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: width,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: N.bg,
            border: Border.all(color: accent ? N.cyan : N.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: N.t(c: color, w: accent ? FontWeight.w700 : FontWeight.w400)),
        ),
      ),
    );
  }
}

/// Moldura de um quadrante: título + área de conteúdo.
class QuadFrame extends StatelessWidget {
  const QuadFrame({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.open = true,
    this.onToggle,
  });
  final String title;
  final Widget child;
  final Widget? trailing;

  /// Modo sanfona: quando [onToggle] existe, o título vira botão e o conteúdo some se [open] for falso.
  /// O conteúdo continua vivo (só escondido), então WebViews e estado não se perdem.
  final bool open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final head = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: open ? const Border(bottom: BorderSide(color: N.line2)) : null,
      ),
      child: Row(
        children: [
          if (onToggle != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: N.cyan),
            ),
          Expanded(
              child: Text(title,
                  style: N.t(c: N.cyan, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          if (trailing != null && open) trailing!,
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: N.line, width: 0.5),
      ),
      child: Column(
        children: [
          onToggle == null ? head : InkWell(onTap: onToggle, child: head),
          Expanded(child: Offstage(offstage: !open, child: ClipRect(child: child))),
        ],
      ),
    );
  }
}
