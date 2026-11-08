import 'dart:math' as math;

import 'package:math_expressions/math_expressions.dart';

import 'ai_router.dart';
import 'notia_brain.dart';

class CalcResult {
  CalcResult(this.text);
  final String text;
}

/// Calculadora em três camadas:
/// 1. avaliador offline (math_expressions), 0 tokens;
/// 2. variáveis e funções financeiras guardadas no SQLite;
/// 3. fallback por IA para problemas em texto, salvando os resultados numéricos.
class HybridCalculatorService {
  HybridCalculatorService(this.brain, this.router);
  final NotiaBrain brain;
  final AiRouter router;

  static final _mathOnly = RegExp(r'^[\d\s\.,\+\-\*/\^%\(\)]+$');
  static final _setRe =
      RegExp(r'^set\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$', caseSensitive: false);
  static const _fin = {'juros', 'price', 'markup', 'margem'};

  /// Esta entrada é resolvida localmente (camadas 1 e 2)?
  bool isCalc(String input) {
    final t = input.trim();
    if (t.startsWith('=') || t.toLowerCase().startsWith('calc:')) return true;
    if (_setRe.hasMatch(t)) return true;
    if (_mathOnly.hasMatch(t) &&
        RegExp(r'\d').hasMatch(t) &&
        RegExp(r'[\+\-\*/\^%]').hasMatch(t)) {
      return true;
    }
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length > 1 && _fin.contains(parts.first.toLowerCase())) {
      return parts.skip(1).every((p) => _num(p) != null);
    }
    return false;
  }

  /// Problema em texto com números: vai para a camada 3 (IA).
  bool needsAi(String p) =>
      RegExp(r'\d').hasMatch(p) &&
      (p.contains('?') ||
          RegExp(r'quant|qual|custo|invest|convers|lucro|margem', caseSensitive: false)
              .hasMatch(p));

  double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  String fmt(num v) {
    if (v is double && (v.isNaN || v.isInfinite)) return 'indefinido';
    var s = v.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
    if (s.isEmpty || s == '-') s = '0';
    return s.replaceAll('.', ',');
  }

  Future<CalcResult> evaluate(String input) async {
    var t = input.trim();

    final set = _setRe.firstMatch(t);
    if (set != null) {
      final name = set.group(1)!;
      final v = await _evalExpr(set.group(2)!);
      await brain.setVar(name, v.toDouble());
      return CalcResult('$name = ${fmt(v)} (salvo)');
    }

    final parts = t.split(RegExp(r'\s+'));
    if (parts.length > 1 && _fin.contains(parts.first.toLowerCase())) {
      return _finance(parts.first.toLowerCase(), parts.skip(1).map((e) => _num(e)!).toList());
    }

    if (t.startsWith('=')) t = t.substring(1);
    if (t.toLowerCase().startsWith('calc:')) t = t.substring(5);
    final v = await _evalExpr(t);
    return CalcResult('= ${fmt(v)}');
  }

  Future<num> _evalExpr(String raw) async {
    var expr = raw.trim();
    if (expr.contains(',') && !expr.contains('.')) expr = expr.replaceAll(',', '.');
    final vars = await brain.getVars();
    final cm = ContextModel();
    vars.forEach((k, v) => cm.bindVariableName(k, Number(v)));
    try {
      final e = Parser().parse(expr);
      final r = e.evaluate(EvaluationType.REAL, cm);
      return r as num;
    } catch (_) {
      throw Exception('expressão inválida ou variável desconhecida');
    }
  }

  CalcResult _finance(String fn, List<double> a) {
    switch (fn) {
      case 'juros': // juros capital taxa% periodos
        if (a.length != 3) throw Exception('use: juros capital taxa% periodos');
        final m = a[0] * math.pow(1 + a[1] / 100, a[2]);
        return CalcResult('Montante: ${fmt(m)} (juros: ${fmt(m - a[0])})');
      case 'price': // price valor taxa% parcelas
        if (a.length != 3) throw Exception('use: price valor taxa% parcelas');
        final i = a[1] / 100;
        final n = a[2];
        final pmt = i == 0 ? a[0] / n : a[0] * i / (1 - math.pow(1 + i, -n));
        return CalcResult(
            'Parcela: ${fmt(pmt)} (total: ${fmt(pmt * n)}, juros: ${fmt(pmt * n - a[0])})');
      case 'markup': // markup custo preco
        if (a.length != 2 || a[0] == 0) throw Exception('use: markup custo preco');
        return CalcResult('Markup: ${fmt((a[1] - a[0]) / a[0] * 100)}%');
      default: // margem custo preco
        if (a.length != 2 || a[1] == 0) throw Exception('use: margem custo preco');
        return CalcResult('Margem: ${fmt((a[1] - a[0]) / a[1] * 100)}%');
    }
  }

  /// Camada 3: a IA resolve em passos e devolve uma linha VARIAVEIS que vira SQLite.
  Future<AiResult> solveWithAi(String prompt) async {
    final r = await router.ask(
        '$prompt\n\nResolva passo a passo, de forma curta. No final escreva uma linha exata: '
        'VARIAVEIS: nome=valor; nome2=valor2 (nomes em snake_case, números com ponto decimal).');
    var text = r.text;
    final m = RegExp(r'VARIAVEIS:\s*(.+)$', multiLine: true).firstMatch(text);
    if (m != null) {
      for (final part in m.group(1)!.split(';')) {
        final kv = part.split('=');
        if (kv.length != 2) continue;
        final k = kv[0].trim();
        final v = double.tryParse(kv[1].trim().replaceAll(',', '.'));
        if (v != null && RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(k)) {
          await brain.setVar(k, v, descricao: 'resultado da IA');
        }
      }
      text = text.replaceFirst(m.group(0)!, '').trim();
    }
    return AiResult(text, r.badge);
  }
}
