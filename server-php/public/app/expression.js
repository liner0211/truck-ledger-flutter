/** 与 Flutter expression_eval.dart 对齐：安全算术表达式（运费等） */
(function (global) {
  function tryEvalExpression(raw) {
    if (raw == null) return null;
    let s = String(raw).trim().replace(/,/g, '.').replace(/\s+/g, '');
    if (!s) return null;
    const plain = Number(s);
    if (Number.isFinite(plain) && /^-?\d+(\.\d+)?$/.test(s)) return plain;
    try {
      const tokens = tokenize(s);
      if (!tokens.length) return null;
      let i = 0;

      function parseExpr() {
        let v = parseTerm();
        while (i < tokens.length && (tokens[i] === '+' || tokens[i] === '-')) {
          const op = tokens[i++];
          const r = parseTerm();
          v = op === '+' ? v + r : v - r;
        }
        return v;
      }

      function parseTerm() {
        let v = parseFactor();
        while (i < tokens.length && (tokens[i] === '*' || tokens[i] === '/')) {
          const op = tokens[i++];
          const r = parseFactor();
          if (op === '*') v *= r;
          else {
            if (r === 0) throw new Error('div0');
            v /= r;
          }
        }
        return v;
      }

      function parseFactor() {
        if (i >= tokens.length) throw new Error('eof');
        const t = tokens[i++];
        let v;
        if (t === '(') {
          v = parseExpr();
          if (i >= tokens.length || tokens[i] !== ')') throw new Error('paren');
          i++;
        } else if (t === '+') {
          v = parseFactor();
        } else if (t === '-') {
          v = -parseFactor();
        } else {
          const n = Number(t);
          if (!Number.isFinite(n)) throw new Error('num');
          v = n;
        }
        while (i < tokens.length && tokens[i] === '%') {
          i++;
          v = v / 100;
        }
        return v;
      }

      const result = parseExpr();
      if (i !== tokens.length) throw new Error('trailing');
      if (!Number.isFinite(result)) return null;
      return Math.round(result * 100) / 100;
    } catch (_) {
      return null;
    }
  }

  function tokenize(s) {
    const out = [];
    let i = 0;
    while (i < s.length) {
      const c = s[i];
      if ('+-*/()%'.includes(c)) {
        out.push(c);
        i++;
        continue;
      }
      if ((c >= '0' && c <= '9') || c === '.') {
        const start = i;
        i++;
        while (i < s.length) {
          const d = s[i];
          if ((d >= '0' && d <= '9') || d === '.') i++;
          else break;
        }
        out.push(s.slice(start, i));
        continue;
      }
      throw new Error('bad char');
    }
    return out;
  }

  global.tryEvalExpression = tryEvalExpression;
})(window);
