/// 安全算术表达式求值（运费等）。
/// 支持：`+ - * /`、括号、小数，以及后缀 `%`（如 `3%` → `0.03`，`8000*3%` → `240`）。
class ExpressionEval {
  ExpressionEval._();

  /// 成功返回数值；失败返回 null。
  static double? tryEval(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().replaceAll(',', '.').replaceAll(' ', '');
    if (s.isEmpty) return null;
    final plain = double.tryParse(s);
    if (plain != null) return plain;
    try {
      final tokens = _tokenize(s);
      if (tokens.isEmpty) return null;
      final result = _Parser(tokens).parse();
      if (result.isNaN || result.isInfinite) return null;
      return (result * 100).roundToDouble() / 100;
    } catch (_) {
      return null;
    }
  }

  static List<String> _tokenize(String s) {
    final out = <String>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if ('+-*/()%'.contains(c)) {
        out.add(c);
        i++;
        continue;
      }
      if ((c.compareTo('0') >= 0 && c.compareTo('9') <= 0) || c == '.') {
        final start = i;
        i++;
        while (i < s.length) {
          final d = s[i];
          if ((d.compareTo('0') >= 0 && d.compareTo('9') <= 0) || d == '.') {
            i++;
          } else {
            break;
          }
        }
        out.add(s.substring(start, i));
        continue;
      }
      throw StateError('bad char');
    }
    return out;
  }
}

class _Parser {
  _Parser(this.tokens);
  final List<String> tokens;
  var i = 0;

  double parse() {
    final result = _expr();
    if (i != tokens.length) throw StateError('trailing');
    return result;
  }

  double _expr() {
    var v = _term();
    while (i < tokens.length && (tokens[i] == '+' || tokens[i] == '-')) {
      final op = tokens[i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _factor();
    while (i < tokens.length && (tokens[i] == '*' || tokens[i] == '/')) {
      final op = tokens[i++];
      final r = _factor();
      if (op == '*') {
        v *= r;
      } else {
        if (r == 0) throw StateError('div0');
        v /= r;
      }
    }
    return v;
  }

  double _factor() {
    if (i >= tokens.length) throw StateError('eof');
    final t = tokens[i++];
    double v;
    if (t == '(') {
      v = _expr();
      if (i >= tokens.length || tokens[i] != ')') throw StateError('paren');
      i++;
    } else if (t == '+') {
      v = _factor();
    } else if (t == '-') {
      v = -_factor();
    } else {
      final n = double.tryParse(t);
      if (n == null) throw StateError('num');
      v = n;
    }
    while (i < tokens.length && tokens[i] == '%') {
      i++;
      v = v / 100.0;
    }
    return v;
  }
}
