/// Normaliza texto para comparação: minúsculas, sem acentos.
String norm(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

String clip(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;
